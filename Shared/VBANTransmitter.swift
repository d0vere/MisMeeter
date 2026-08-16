import Darwin
import Foundation
import os

final class VBANTransmitter {
    private let configQueue = DispatchQueue(
        label: "dev.mismeeter.vban.config",
        qos: .userInitiated
    )

    private let diagnosticsQueue = DispatchQueue(
        label: "dev.mismeeter.vban.diagnostics",
        qos: .utility
    )

    private let muteLock = OSAllocatedUnfairLock(initialState: false)

    private var socketFD: Int32 = -1
    private var packetBuffer: UnsafeMutableRawPointer?
    private let packetByteCount = 28 + VBANPacket.samplesPerPacket * 2

    private var frameCounter: UInt32 = 0
    private var packetsSent: UInt64 = 0
    private var sendErrors: UInt64 = 0

    private var remainder: [Int16] = []

    private var lastSendNS: UInt64?
    private var maxSendGapMS: Double = 0

    private var captureWindowStartNS: UInt64?
    private var captureSamples: UInt64 = 0
    private var measuredCaptureRate: Double = 48_000

    private var txWindowStartNS: UInt64?
    private var txSamples: UInt64 = 0
    private var measuredTXRate: Double = 48_000

    private var diagnosticPacketCounter = 0

    private var transportState: TransportState = .foregroundRealtime

    private(set) var preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

    var onStateChange: ((String) -> Void)?
    var onBufferLevel: ((Int) -> Void)?
    var onUnderruns: ((UInt64) -> Void)?
    var onPacketsSent: ((UInt64) -> Void)?
    var onPrimedChange: ((Bool) -> Void)?
    var onPLLStats: ((Double, Double, Double, Double, UInt64) -> Void)?
    var onTransportMode: ((TransportState, Int, Int, Double) -> Void)?

    init() {
        packetBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: packetByteCount,
            alignment: 16
        )
    }

    deinit {
        closeSocket()
        packetBuffer?.deallocate()
    }

    func configure(
        preset: VBANPreset,
        transmissionMode: VBANTransmissionMode
    ) {
        configQueue.sync {
            self.preset = preset
        }
    }

    func start() {
        configQueue.async {
            self.closeSocket()

            let host = self.preset.host
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !host.isEmpty else {
                self.onStateChange?("Invalid VBAN destination")
                return
            }

            // v1.2 intentionally uses direct IPv4 UDP to keep the realtime
            // path deterministic. Hostnames are not resolved on the audio thread.
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = self.preset.port.bigEndian

            let conversion = host.withCString {
                inet_pton(AF_INET, $0, &destination.sin_addr)
            }

            guard conversion == 1 else {
                self.onStateChange?(
                    "Realtime UDP requires an IPv4 address (example: 192.168.1.50)"
                )
                return
            }

            let fd = Darwin.socket(
                AF_INET,
                Int32(SOCK_DGRAM.rawValue),
                IPPROTO_UDP
            )

            guard fd >= 0 else {
                self.onStateChange?("Could not create UDP socket")
                return
            }

            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

            var sendBufferSize: Int32 = 1_048_576
            withUnsafePointer(to: &sendBufferSize) {
                _ = setsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_SNDBUF,
                    $0,
                    socklen_t(MemoryLayout<Int32>.size)
                )
            }

            let connectResult: Int32 = withUnsafePointer(
                to: &destination
            ) { pointer in
                pointer.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1
                ) {
                    Darwin.connect(
                        fd,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }

            guard connectResult == 0 else {
                Darwin.close(fd)
                self.onStateChange?("Could not connect UDP socket")
                return
            }

            self.socketFD = fd
            self.frameCounter = 0
            self.packetsSent = 0
            self.sendErrors = 0
            self.remainder.removeAll(keepingCapacity: true)
            self.lastSendNS = nil
            self.maxSendGapMS = 0

            self.captureWindowStartNS = nil
            self.captureSamples = 0
            self.measuredCaptureRate = 48_000

            self.txWindowStartNS = nil
            self.txSamples = 0
            self.measuredTXRate = 48_000

            self.writeStaticHeader()
            self.onStateChange?("VBAN realtime socket ready")
            self.onPrimedChange?(true)
            self.publishDiagnostics()
        }
    }

    func stop() {
        configQueue.async {
            self.closeSocket()
            self.onPrimedChange?(false)
            self.onStateChange?("Stopped")
        }
    }

    func setMuted(_ value: Bool) {
        muteLock.withLock {
            $0 = value
        }
    }

    func beginLockTransition() {
        transportState = .lockTransition
        publishDiagnostics()
    }

    func enterBackground() {
        transportState = .backgroundStable
        publishDiagnostics()
    }

    func enterForeground() {
        transportState = .foregroundRealtime
        publishDiagnostics()
    }

    /// Called from AVAudioSinkNode's realtime render cadence.
    /// The common path is exactly 256 frames and performs a single nonblocking
    /// send() syscall without dispatching through a GCD networking queue.
    func enqueue(_ samples: [Int16]) {
        guard socketFD >= 0, !samples.isEmpty else { return }

        updateCaptureRate(sampleCount: samples.count)

        if remainder.isEmpty &&
            samples.count == VBANPacket.samplesPerPacket {
            sendRealtimePacket(samples)
        } else {
            remainder.append(contentsOf: samples)

            while remainder.count >= VBANPacket.samplesPerPacket {
                let block = Array(
                    remainder.prefix(VBANPacket.samplesPerPacket)
                )

                remainder.removeFirst(
                    VBANPacket.samplesPerPacket
                )

                sendRealtimePacket(block)
            }
        }

        diagnosticPacketCounter += 1

        // Keep UI diagnostics off the realtime path most of the time.
        if diagnosticPacketCounter >= 94 {
            diagnosticPacketCounter = 0
            let sent = packetsSent
            let gap = maxSendGapMS
            let capture = measuredCaptureRate
            let tx = measuredTXRate
            let errors = sendErrors
            let state = transportState
            let buffered = remainder.count

            diagnosticsQueue.async { [weak self] in
                guard let self else { return }

                self.onPacketsSent?(sent)
                self.onBufferLevel?(buffered)
                self.onUnderruns?(errors)
                self.onPLLStats?(0, capture, tx, 0, 0)
                self.onTransportMode?(
                    state,
                    1,
                    buffered,
                    gap
                )
            }
        }
    }

    private func sendRealtimePacket(_ samples: [Int16]) {
        guard
            samples.count == VBANPacket.samplesPerPacket,
            let packetBuffer,
            socketFD >= 0
        else {
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds

        if let previous = lastSendNS {
            let gap =
                Double(now - previous) / 1_000_000.0

            maxSendGapMS = max(maxSendGapMS, gap)
        }

        lastSendNS = now

        let bytes = packetBuffer.bindMemory(
            to: UInt8.self,
            capacity: packetByteCount
        )

        // frame counter bytes 24...27, little endian
        var frame = frameCounter.littleEndian
        withUnsafeBytes(of: &frame) { source in
            for index in 0..<4 {
                bytes[24 + index] = source[index]
            }
        }

        let isMuted = muteLock.withLock { $0 }

        // PCM begins at byte 28.
        for index in 0..<VBANPacket.samplesPerPacket {
            let value: Int16 =
                isMuted ? 0 : samples[index]

            let u = UInt16(
                bitPattern: value
            ).littleEndian

            bytes[28 + index * 2] =
                UInt8(truncatingIfNeeded: u)

            bytes[29 + index * 2] =
                UInt8(truncatingIfNeeded: u >> 8)
        }

        let result = Darwin.send(
            socketFD,
            packetBuffer,
            packetByteCount,
            0
        )

        if result == packetByteCount {
            frameCounter &+= 1
            packetsSent &+= 1
            updateTXRate(sampleCount: VBANPacket.samplesPerPacket)
        } else {
            // Nonblocking socket: never wait on the network from the audio thread.
            sendErrors &+= 1
        }
    }

    private func writeStaticHeader() {
        guard let packetBuffer else { return }

        let bytes = packetBuffer.bindMemory(
            to: UInt8.self,
            capacity: packetByteCount
        )

        for i in 0..<packetByteCount {
            bytes[i] = 0
        }

        bytes[0] = 0x56 // V
        bytes[1] = 0x42 // B
        bytes[2] = 0x41 // A
        bytes[3] = 0x4E // N

        bytes[4] = VBANPacket.sampleRateIndex
        bytes[5] = UInt8(
            VBANPacket.samplesPerPacket - 1
        )
        bytes[6] = 0 // mono => channels - 1
        bytes[7] = 0x01 // native PCM / Int16

        let stream = Array(
            preset.sanitizedStreamName.utf8.prefix(16)
        )

        for (index, byte) in stream.enumerated() {
            bytes[8 + index] = byte
        }
    }

    private func updateCaptureRate(sampleCount: Int) {
        let now = DispatchTime.now().uptimeNanoseconds

        if captureWindowStartNS == nil {
            captureWindowStartNS = now
            captureSamples = UInt64(sampleCount)
            return
        }

        captureSamples += UInt64(sampleCount)

        guard let start = captureWindowStartNS else { return }
        let elapsed = now - start

        guard elapsed >= 2_000_000_000 else { return }

        let seconds =
            Double(elapsed) / 1_000_000_000.0

        let rate =
            Double(captureSamples) / seconds

        if rate > 44_000 && rate < 52_000 {
            measuredCaptureRate =
                measuredCaptureRate * 0.82 +
                rate * 0.18
        }

        captureWindowStartNS = now
        captureSamples = 0
    }

    private func updateTXRate(sampleCount: Int) {
        let now = DispatchTime.now().uptimeNanoseconds

        if txWindowStartNS == nil {
            txWindowStartNS = now
            txSamples = UInt64(sampleCount)
            return
        }

        txSamples += UInt64(sampleCount)

        guard let start = txWindowStartNS else { return }
        let elapsed = now - start

        guard elapsed >= 2_000_000_000 else { return }

        let seconds =
            Double(elapsed) / 1_000_000_000.0

        let rate =
            Double(txSamples) / seconds

        if rate > 44_000 && rate < 52_000 {
            measuredTXRate =
                measuredTXRate * 0.82 +
                rate * 0.18
        }

        txWindowStartNS = now
        txSamples = 0
    }

    private func publishDiagnostics() {
        let state = transportState
        let gap = maxSendGapMS
        let buffer = remainder.count

        diagnosticsQueue.async { [weak self] in
            guard let self else { return }

            self.onPLLStats?(
                0,
                self.measuredCaptureRate,
                self.measuredTXRate,
                0,
                0
            )

            self.onTransportMode?(
                state,
                1,
                buffer,
                gap
            )
        }
    }

    private func closeSocket() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }
}

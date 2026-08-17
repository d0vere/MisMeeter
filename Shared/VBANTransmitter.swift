import Darwin
import Foundation
import os

enum VBANTransmitterError: LocalizedError {
    case invalidDestination
    case socketCreation
    case socketConnection

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "Use a valid IPv4 destination, for example 192.168.1.50."
        case .socketCreation:
            return "Could not create the VBAN UDP socket."
        case .socketConnection:
            return "Could not connect the VBAN UDP socket to the destination."
        }
    }
}

/// Realtime VBAN sender.
///
/// The microphone callback is the TX clock. PCM is packetized and sent from that
/// callback through a connected, nonblocking UDP socket. There is deliberately
/// no DispatchQueue/semaphore/timer between Core Audio and UDP: background
/// scheduler throttling can therefore not turn stable microphone callbacks into
/// irregular network bursts.
final class VBANTransmitter {
    private let diagnosticsQueue = DispatchQueue(
        label: "dev.mismeeter.vban.diagnostics",
        qos: .utility
    )

    private let muteLock = OSAllocatedUnfairLock(initialState: false)

    private var socketFD: Int32 = -1
    private var packetBuffer: UnsafeMutableRawPointer?
    private let packetByteCount = 28 + VBANPacket.samplesPerPacket * 2
    private var packetSampleCursor = 0

    private var frameCounter: UInt32 = 0
    private var packetsSent: UInt64 = 0
    private var sendErrors: UInt64 = 0
    private var droppedPackets: UInt64 = 0

    private var lastSendNS: UInt64?
    private var maxSendGapMS: Double = 0
    private var captureWindowStartNS: UInt64?
    private var captureSamples: UInt64 = 0
    private var measuredCaptureRate: Double = VBANPacket.sampleRate
    private var txWindowStartNS: UInt64?
    private var txSamples: UInt64 = 0
    private var measuredTXRate: Double = VBANPacket.sampleRate
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

    func configure(preset: VBANPreset, transmissionMode: VBANTransmissionMode) {
        self.preset = preset
    }

    /// Opens the socket synchronously before microphone capture starts.
    /// This removes the former race where the first audio callbacks could arrive
    /// while the configuration queue was still opening the UDP socket.
    func start() throws {
        closeSocket()

        let host = preset.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw VBANTransmitterError.invalidDestination }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = preset.port.bigEndian

        let converted = host.withCString { inet_pton(AF_INET, $0, &destination.sin_addr) }
        guard converted == 1 else { throw VBANTransmitterError.invalidDestination }

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw VBANTransmitterError.socketCreation }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var sendBufferSize: Int32 = 1_048_576
        withUnsafePointer(to: &sendBufferSize) {
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDBUF, $0, socklen_t(MemoryLayout<Int32>.size))
        }

        #if os(iOS)
        var noSigPipe: Int32 = 1
        withUnsafePointer(to: &noSigPipe) {
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        #endif

        let result: Int32 = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard result == 0 else {
            Darwin.close(fd)
            throw VBANTransmitterError.socketConnection
        }

        socketFD = fd
        frameCounter = 0
        packetsSent = 0
        sendErrors = 0
        droppedPackets = 0
        packetSampleCursor = 0
        lastSendNS = nil
        maxSendGapMS = 0
        captureWindowStartNS = nil
        captureSamples = 0
        measuredCaptureRate = VBANPacket.sampleRate
        txWindowStartNS = nil
        txSamples = 0
        measuredTXRate = VBANPacket.sampleRate
        writeStaticHeader()
        onStateChange?("VBAN realtime ready")
        onPrimedChange?(true)
        publishDiagnostics()
    }

    func stop() {
        closeSocket()
        packetSampleCursor = 0
        onPrimedChange?(false)
        onStateChange?("Stopped")
    }

    func setMuted(_ value: Bool) {
        muteLock.withLock { $0 = value }
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

    /// Called only from the Core Audio input callback.
    /// No heap allocations, no waits, no dispatches and a nonblocking socket.
    func sendPCM16(_ source: UnsafePointer<Int16>, frameCount: Int) {
        guard socketFD >= 0, frameCount > 0, let packetBuffer else { return }

        updateCaptureRate(sampleCount: frameCount)
        let muted = muteLock.withLock { $0 }
        let bytes = packetBuffer.bindMemory(to: UInt8.self, capacity: packetByteCount)

        for index in 0..<frameCount {
            let sample: Int16 = muted ? 0 : source[index]
            let little = UInt16(bitPattern: sample).littleEndian
            let offset = 28 + packetSampleCursor * 2
            bytes[offset] = UInt8(truncatingIfNeeded: little)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: little >> 8)
            packetSampleCursor += 1

            if packetSampleCursor == VBANPacket.samplesPerPacket {
                sendCurrentPacket(bytes: bytes)
                packetSampleCursor = 0
            }
        }
    }

    private func sendCurrentPacket(bytes: UnsafeMutablePointer<UInt8>) {
        var frame = frameCounter.littleEndian
        withUnsafeBytes(of: &frame) { raw in
            bytes[24] = raw[0]
            bytes[25] = raw[1]
            bytes[26] = raw[2]
            bytes[27] = raw[3]
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if let previous = lastSendNS {
            maxSendGapMS = max(maxSendGapMS, Double(now - previous) / 1_000_000.0)
        }
        lastSendNS = now

        let sent = Darwin.send(socketFD, packetBuffer, packetByteCount, 0)
        if sent == packetByteCount {
            frameCounter &+= 1
            packetsSent &+= 1
            updateTXRate(sampleCount: VBANPacket.samplesPerPacket)
        } else {
            sendErrors &+= 1
            droppedPackets &+= 1
        }

        diagnosticPacketCounter += 1
        if diagnosticPacketCounter >= 94 {
            diagnosticPacketCounter = 0
            publishDiagnostics()
        }
    }

    private func writeStaticHeader() {
        guard let packetBuffer else { return }
        let bytes = packetBuffer.bindMemory(to: UInt8.self, capacity: packetByteCount)
        for i in 0..<packetByteCount { bytes[i] = 0 }
        bytes[0] = 0x56; bytes[1] = 0x42; bytes[2] = 0x41; bytes[3] = 0x4E
        bytes[4] = VBANPacket.sampleRateIndex
        bytes[5] = UInt8(VBANPacket.samplesPerPacket - 1)
        bytes[6] = 0
        bytes[7] = 0x01
        for (index, byte) in Array(preset.sanitizedStreamName.utf8.prefix(16)).enumerated() {
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
        guard let start = captureWindowStartNS, now - start >= 2_000_000_000 else { return }
        let rate = Double(captureSamples) / (Double(now - start) / 1_000_000_000.0)
        if rate > 44_000, rate < 52_000 { measuredCaptureRate = measuredCaptureRate * 0.82 + rate * 0.18 }
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
        guard let start = txWindowStartNS, now - start >= 2_000_000_000 else { return }
        let rate = Double(txSamples) / (Double(now - start) / 1_000_000_000.0)
        if rate > 44_000, rate < 52_000 { measuredTXRate = measuredTXRate * 0.82 + rate * 0.18 }
        txWindowStartNS = now
        txSamples = 0
    }

    private func publishDiagnostics() {
        let sent = packetsSent
        let errors = sendErrors
        let capture = measuredCaptureRate
        let tx = measuredTXRate
        let gap = maxSendGapMS
        let state = transportState
        let remainder = packetSampleCursor
        let dropped = droppedPackets

        diagnosticsQueue.async { [weak self] in
            guard let self else { return }
            self.onPacketsSent?(sent)
            self.onBufferLevel?(remainder)
            self.onUnderruns?(errors)
            self.onPLLStats?(0, capture, tx, 0, dropped)
            self.onTransportMode?(state, 1, remainder, gap)
        }
    }

    private func closeSocket() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }
}

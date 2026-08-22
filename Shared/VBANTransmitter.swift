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
/// callback through a connected, nonblocking UDP socket. Realtime code never
/// dispatches work to another queue and never queries AVAudioSession.
final class VBANTransmitter {
    private struct DiagnosticsState {
        var packetsSent: UInt64 = 0
        var sendErrors: UInt64 = 0
        var lastSendNS: UInt64?
        var maxSendGapMS: Double = 0
        var captureWindowStartNS: UInt64?
        var captureSamples: UInt64 = 0
        var measuredCaptureRate: Double = VBANPacket.sampleRate
        var txWindowStartNS: UInt64?
        var txSamples: UInt64 = 0
        var measuredTXRate: Double = VBANPacket.sampleRate
    }

    private let diagnosticsQueue = DispatchQueue(
        label: "dev.mismeeter.vban.diagnostics",
        qos: .utility
    )
    private let diagnosticsLock = OSAllocatedUnfairLock(initialState: DiagnosticsState())
    private let muteLock = OSAllocatedUnfairLock(initialState: false)

    private var diagnosticsTimer: DispatchSourceTimer?
    private var socketFD: Int32 = -1
    private var packetBuffer: UnsafeMutableRawPointer?
    private let packetByteCount = 28 + VBANPacket.samplesPerPacket * 2
    private var packetSampleCursor = 0
    private var frameCounter: UInt32 = 0

    private(set) var preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

    /// packetsSent, sendErrors, captureRate, transmittedRate, maxSendGapMS
    var onDiagnostics: ((UInt64, UInt64, Double, Double, Double) -> Void)?

    init() {
        packetBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: packetByteCount,
            alignment: 16
        )
    }

    deinit {
        stopDiagnosticsTimer()
        closeSocket()
        packetBuffer?.deallocate()
    }

    func configure(preset: VBANPreset) {
        self.preset = preset
    }

    /// Opens the socket synchronously before microphone capture starts.
    func start() throws {
        closeSocket()
        stopDiagnosticsTimer()

        let host = preset.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, preset.port > 0 else {
            throw VBANTransmitterError.invalidDestination
        }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = preset.port.bigEndian

        let converted = host.withCString { inet_pton(AF_INET, $0, &destination.sin_addr) }
        guard converted == 1 else { throw VBANTransmitterError.invalidDestination }

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw VBANTransmitterError.socketCreation }

        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

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
        packetSampleCursor = 0
        diagnosticsLock.withLock { $0 = DiagnosticsState() }
        writeStaticHeader()
        startDiagnosticsTimer()
        publishDiagnostics()
    }

    func stop() {
        stopDiagnosticsTimer()
        closeSocket()
        packetSampleCursor = 0
    }

    func setMuted(_ value: Bool) {
        muteLock.withLock { $0 = value }
    }

    /// Called only from the Core Audio input callback.
    /// No heap allocations, queue dispatches or blocking framework APIs.
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
        let sent = Darwin.send(socketFD, packetBuffer, packetByteCount, 0)
        let didSend = sent == packetByteCount
        // VBAN frame numbers describe packet generation, not local socket success.
        // Advancing even on EAGAIN lets the receiver observe the dropped audio frame.
        frameCounter &+= 1

        diagnosticsLock.withLock { state in
            if let previous = state.lastSendNS {
                state.maxSendGapMS = max(
                    state.maxSendGapMS,
                    Double(now - previous) / 1_000_000.0
                )
            }
            state.lastSendNS = now

            if didSend {
                state.packetsSent &+= 1
                updateTXRate(sampleCount: VBANPacket.samplesPerPacket, now: now, state: &state)
            } else {
                state.sendErrors &+= 1
            }
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
        for (index, byte) in preset.sanitizedStreamName.utf8.prefix(16).enumerated() {
            bytes[8 + index] = byte
        }
    }

    private func updateCaptureRate(sampleCount: Int) {
        let now = DispatchTime.now().uptimeNanoseconds
        diagnosticsLock.withLock { state in
            if state.captureWindowStartNS == nil {
                state.captureWindowStartNS = now
                state.captureSamples = UInt64(sampleCount)
                return
            }

            state.captureSamples &+= UInt64(sampleCount)
            guard let start = state.captureWindowStartNS,
                  now - start >= 2_000_000_000 else {
                return
            }

            let rate = Double(state.captureSamples) / (Double(now - start) / 1_000_000_000.0)
            if rate > 44_000, rate < 52_000 {
                state.measuredCaptureRate = state.measuredCaptureRate * 0.82 + rate * 0.18
            }
            state.captureWindowStartNS = now
            state.captureSamples = 0
        }
    }

    private func updateTXRate(
        sampleCount: Int,
        now: UInt64,
        state: inout DiagnosticsState
    ) {
        if state.txWindowStartNS == nil {
            state.txWindowStartNS = now
            state.txSamples = UInt64(sampleCount)
            return
        }

        state.txSamples &+= UInt64(sampleCount)
        guard let start = state.txWindowStartNS,
              now - start >= 2_000_000_000 else {
            return
        }

        let rate = Double(state.txSamples) / (Double(now - start) / 1_000_000_000.0)
        if rate > 44_000, rate < 52_000 {
            state.measuredTXRate = state.measuredTXRate * 0.82 + rate * 0.18
        }
        state.txWindowStartNS = now
        state.txSamples = 0
    }

    private func startDiagnosticsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: diagnosticsQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(250),
            repeating: .milliseconds(500),
            leeway: .milliseconds(50)
        )
        timer.setEventHandler { [weak self] in
            self?.publishDiagnostics()
        }
        diagnosticsTimer = timer
        timer.resume()
    }

    private func stopDiagnosticsTimer() {
        diagnosticsTimer?.setEventHandler {}
        diagnosticsTimer?.cancel()
        diagnosticsTimer = nil
    }

    private func publishDiagnostics() {
        let snapshot = diagnosticsLock.withLock { state in
            (
                state.packetsSent,
                state.sendErrors,
                state.measuredCaptureRate,
                state.measuredTXRate,
                state.maxSendGapMS
            )
        }
        onDiagnostics?(snapshot.0, snapshot.1, snapshot.2, snapshot.3, snapshot.4)
    }

    private func closeSocket() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }
}

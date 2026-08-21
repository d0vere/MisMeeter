import AVFoundation
import Darwin
import Foundation
import os

enum VBANReceiverError: LocalizedError {
    case socketCreation
    case bindFailed(UInt16)
    case audioFormat
    case audioOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .socketCreation:
            return "Could not create the VBAN receive UDP socket."
        case .bindFailed(let port):
            return "Could not bind UDP port \(port). It may already be in use."
        case .audioFormat:
            return "Could not create the 48 kHz stereo playback format."
        case .audioOutputUnavailable:
            return "The iPhone audio output is not available."
        }
    }
}

final class VBANReceiver {
    private let networkQueue = DispatchQueue(
        label: "dev.mismeeter.vban.rx",
        qos: .userInteractive
    )

    private let controlQueue = DispatchQueue(
        label: "dev.mismeeter.vban.rx.control",
        qos: .userInitiated
    )

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var timePitch: AVAudioUnitTimePitch?

    private let ring = PlaybackRingBuffer()

    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var controlTimer: DispatchSourceTimer?
    private var configurationObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var transmitterActiveForSession = false

    private var expectedStreamName = "MisMeeterRX"
    private var listenPort: UInt16 = 6980

    // Fully automatic receive jitter target. Start conservatively, then converge
    // toward the minimum measured-safe latency. Underflows raise the margin
    // immediately; stable windows lower it gradually.
    private let autoMinimumTargetMS: Double = 20
    private let autoStartupTargetMS: Double = 35
    private let autoMaximumTargetMS: Double = 250

    private var adaptiveTargetMS: Double = 35
    private var adaptiveSafetyMarginMS: Double = 15

    private struct ArrivalJitterState {
        var lastArrivalNS: UInt64?
        var lastFrameCounter: UInt32?
        var smoothedDeviationMS: Double = 0
        var peakDeviationMS: Double = 0
    }

    private let arrivalJitter = OSAllocatedUnfairLock(
        initialState: ArrivalJitterState()
    )

    // Reused decode buffers: avoids two heap allocations for every VBAN packet.
    private var decodeLeft = [Float](repeating: 0, count: 256)
    private var decodeRight = [Float](repeating: 0, count: 256)

    private var packetsReceived: UInt64 = 0
    private var packetsRejected: UInt64 = 0
    private var lastFrameCounter: UInt32?
    private var lostFrames: UInt64 = 0

    private var lastUnderflowCount: UInt64 = 0
    private var stableControlWindows = 0
    private var currentRate: Float = 1.0

    private(set) var isRunning = false
    private(set) var isOutputMuted = false

    var onStatus: ((String) -> Void)?

    /// received, rejected, lost, bufferedFrames, underflows, primed, playbackRate, targetMS
    var onDiagnostics: ((
        UInt64,
        UInt64,
        UInt64,
        Int,
        UInt64,
        Bool,
        Float,
        Double
    ) -> Void)?

    init() {
        installAudioObservers()
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func start(
        preset: VBANReceivePreset,
        transmitterAlreadyActive: Bool
    ) throws {
        stop(deactivateSession: false)

        expectedStreamName =
            preset.sanitizedStreamName

        listenPort = preset.port

        adaptiveTargetMS = autoStartupTargetMS
        adaptiveSafetyMarginMS = max(
            0,
            autoStartupTargetMS - autoMinimumTargetMS
        )

        arrivalJitter.withLock { state in
            state = ArrivalJitterState()
        }

        ring.reset(
            targetFrames: frames(forMS: adaptiveTargetMS)
        )

        transmitterActiveForSession = transmitterAlreadyActive
        try AudioSessionCoordinator.shared.ensureReceivePlayback(
            transmitterActive: transmitterAlreadyActive
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate:
                VBANPacket.sampleRate,
            channels: 2
        ) else {
            throw VBANReceiverError.audioFormat
        }

        let node = AVAudioSourceNode(
            format: format
        ) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else {
                return noErr
            }

            let buffers =
                UnsafeMutableAudioBufferListPointer(
                    audioBufferList
                )

            guard buffers.count >= 2,
                  let leftData =
                    buffers[0].mData,
                  let rightData =
                    buffers[1].mData
            else {
                for buffer in buffers {
                    if let data = buffer.mData {
                        memset(
                            data,
                            0,
                            Int(buffer.mDataByteSize)
                        )
                    }
                }

                return noErr
            }

            let left =
                leftData.assumingMemoryBound(
                    to: Float.self
                )

            let right =
                rightData.assumingMemoryBound(
                    to: Float.self
                )

            self.ring.render(
                frameCount: Int(frameCount),
                left: left,
                right: right
            )

            return noErr
        }

        let speed = AVAudioUnitTimePitch()
        speed.rate = 1.0
        speed.pitch = 0
        speed.overlap = 8.0

        sourceNode = node
        timePitch = speed

        engine.attach(node)
        engine.attach(speed)

        engine.connect(
            node,
            to: speed,
            format: format
        )

        engine.connect(
            speed,
            to: engine.mainMixerNode,
            format: format
        )

        // Accessing mainMixerNode creates and connects the engine's output path.
        // Leave the mixer -> output format implicit so AVAudioEngine can track
        // hardware route changes automatically.
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        guard outputFormat.sampleRate > 0, outputFormat.channelCount > 0 else {
            engine.detach(node)
            engine.detach(speed)
            sourceNode = nil
            timePitch = nil
            throw VBANReceiverError.audioOutputUnavailable
        }

        engine.mainMixerNode.outputVolume = 1.0
        isOutputMuted = false
        engine.prepare()
        try engine.start()

        if transmitterAlreadyActive {
            AudioSessionCoordinator.shared.forceSpeaker()
        }

        do {
            try openSocket()
        } catch {
            engine.stop()
            engine.detach(node)
            engine.detach(speed)
            sourceNode = nil
            timePitch = nil
            throw error
        }

        packetsReceived = 0
        packetsRejected = 0
        lastFrameCounter = nil
        lostFrames = 0
        lastUnderflowCount = 0
        stableControlWindows = 0
        currentRate = 1.0

        isRunning = true

        startClockRecovery()

        onStatus?(
            "Listening • \(expectedStreamName) • UDP \(listenPort)"
        )
    }

    func stop(
        deactivateSession: Bool
    ) {
        isRunning = false
        isOutputMuted = false
        transmitterActiveForSession = false

        controlTimer?.setEventHandler {}
        controlTimer?.cancel()
        controlTimer = nil

        if let source = readSource {
            source.setEventHandler {}
            source.cancel()
            readSource = nil
        }

        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }

        engine.stop()

        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            sourceNode = nil
        }

        if let speed = timePitch {
            engine.disconnectNodeOutput(speed)
            engine.detach(speed)
            timePitch = nil
        }

        ring.reset(
            targetFrames:
                frames(forMS: autoStartupTargetMS)
        )

        if deactivateSession {
            AudioSessionCoordinator.shared
                .deactivateIfPossible()
        }

        onStatus?("Receiver stopped")
    }


    func setOutputMuted(_ muted: Bool) {
        guard isRunning else {
            isOutputMuted = false
            return
        }
        isOutputMuted = muted
        engine.mainMixerNode.outputVolume = muted ? 0.0 : 1.0
        onStatus?(muted ? "Receive muted" : "Listening • \(expectedStreamName) • UDP \(listenPort)")
    }

    /// Called when TX starts/stops while RX keeps running. Reasserting the
    /// session and restarting a stopped engine prevents category transitions
    /// from leaving a graph that still reports packets but produces no sound.
    func refreshAudioSession(transmitterActive: Bool) {
        guard isRunning else { return }
        transmitterActiveForSession = transmitterActive
        do {
            try AudioSessionCoordinator.shared.ensureReceivePlayback(
                transmitterActive: transmitterActive
            )
            if transmitterActive {
                AudioSessionCoordinator.shared.forceSpeaker()
            }
            recoverOutputEngineIfNeeded(forceRestart: true)
        } catch {
            onStatus?("Audio output error • \(error.localizedDescription)")
        }
    }

    private func installAudioObservers() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            // Apple stops/uninitializes the engine before posting this notification.
            // The nodes stay attached, so restarting the existing graph is sufficient.
            self?.recoverOutputEngineIfNeeded(forceRestart: false)
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            do {
                try AudioSessionCoordinator.shared.ensureReceivePlayback(
                    transmitterActive: self.transmitterActiveForSession
                )
                if self.transmitterActiveForSession {
                    AudioSessionCoordinator.shared.forceSpeaker()
                }
            } catch {
                self.onStatus?("Audio route error • \(error.localizedDescription)")
            }
            self.recoverOutputEngineIfNeeded(forceRestart: false)
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self, self.isRunning,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw),
                  type == .ended else { return }
            do {
                try AudioSessionCoordinator.shared.ensureReceivePlayback(
                    transmitterActive: self.transmitterActiveForSession
                )
            } catch {
                self.onStatus?("Audio resume error • \(error.localizedDescription)")
            }
            self.recoverOutputEngineIfNeeded(forceRestart: true)
        }
    }

    private func recoverOutputEngineIfNeeded(forceRestart: Bool) {
        guard isRunning, sourceNode != nil else { return }
        controlQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            do {
                if forceRestart && self.engine.isRunning {
                    self.engine.stop()
                }
                if !self.engine.isRunning {
                    self.engine.prepare()
                    try self.engine.start()
                }
                self.engine.mainMixerNode.outputVolume = self.isOutputMuted ? 0.0 : 1.0
            } catch {
                self.onStatus?("Audio engine error • \(error.localizedDescription)")
            }
        }
    }

    private func startClockRecovery() {
        controlTimer?.cancel()

        let timer =
            DispatchSource.makeTimerSource(
                queue: controlQueue
            )

        timer.schedule(
            deadline: .now() + 0.5,
            repeating: .milliseconds(500),
            leeway: .milliseconds(20)
        )

        timer.setEventHandler { [weak self] in
            self?.updateClockRecovery()
        }

        controlTimer = timer
        timer.resume()
    }

    /// VBAN sender and iPhone hardware have independent clocks.
    /// Playback rate correction handles slow clock drift while the automatic
    /// jitter controller handles packet-arrival variation. The target is not a
    /// user preference: it continuously converges toward the lowest stable value.
    private func updateClockRecovery() {
        guard isRunning else { return }

        let stats = ring.stats()
        let targetFrames = max(256, ring.targetFrames())

        let error = Double(stats.bufferedFrames - targetFrames) / Double(targetFrames)

        // A slightly wider dead-zone is calmer at the new low-latency targets.
        let effectiveError = abs(error) < 0.10 ? 0 : error

        // TimePitch preserves pitch while correcting independent sender/device clocks.
        let desiredRate = Float(
            max(
                0.98,
                min(1.02, 1.0 + effectiveError * 0.015)
            )
        )

        currentRate = currentRate * 0.82 + desiredRate * 0.18

        DispatchQueue.main.async { [weak self] in
            self?.timePitch?.rate = self?.currentRate ?? 1.0
        }

        let hadNewUnderflow = stats.underflows != lastUnderflowCount
        var allowTargetDecrease = false

        if hadNewUnderflow {
            // React quickly to instability. A 25 ms step is large enough to recover
            // in a few windows without jumping straight to triple-digit latency.
            adaptiveSafetyMarginMS = min(
                autoMaximumTargetMS - autoMinimumTargetMS,
                adaptiveSafetyMarginMS + 25
            )
            stableControlWindows = 0
        } else if stats.primed {
            stableControlWindows += 1

            // Ten seconds of clean playback earns a small latency reduction.
            if stableControlWindows >= 20 {
                adaptiveSafetyMarginMS = max(0, adaptiveSafetyMarginMS - 5)
                stableControlWindows = 0
                allowTargetDecrease = true
            }
        } else {
            stableControlWindows = 0
        }

        let measuredBaseMS = automaticMeasuredBaseTargetMS()
        let desiredTargetMS = min(
            autoMaximumTargetMS,
            max(autoMinimumTargetMS, measuredBaseMS + adaptiveSafetyMarginMS)
        )

        if hadNewUnderflow || desiredTargetMS > adaptiveTargetMS + 1 {
            adaptiveTargetMS = desiredTargetMS
            ring.setTargetFrames(
                frames(forMS: adaptiveTargetMS),
                forceReprimeIfBelowTarget: hadNewUnderflow
            )
        } else if allowTargetDecrease && desiredTargetMS < adaptiveTargetMS - 1 {
            // Lower in small steps to avoid oscillating around the stability edge.
            adaptiveTargetMS = max(desiredTargetMS, adaptiveTargetMS - 5)
            ring.setTargetFrames(
                frames(forMS: adaptiveTargetMS),
                forceReprimeIfBelowTarget: false
            )
        }

        lastUnderflowCount = stats.underflows

        let diagnosticsRate = currentRate
        let diagnosticsTargetMS = adaptiveTargetMS
        networkQueue.async { [weak self] in
            self?.publishDiagnostics(
                playbackRate: diagnosticsRate,
                targetMS: diagnosticsTargetMS
            )
        }
    }

    private func automaticMeasuredBaseTargetMS() -> Double {
        let metrics = arrivalJitter.withLock { state in
            (state.smoothedDeviationMS, state.peakDeviationMS)
        }

        // Four nominal VBAN packets give the decoder/audio thread enough runway on
        // a clean LAN. Measured deviation then adds only the margin the network needs.
        let packetMS = VBANPacket.packetDurationSeconds * 1000.0
        let networkMargin = metrics.0 * 4.0 + metrics.1 * 1.5

        return min(
            autoMaximumTargetMS,
            max(autoMinimumTargetMS, packetMS * 4.0 + networkMargin)
        )
    }

    private func recordPacketArrival(frame: UInt32, sampleCount: Int) {
        let now = DispatchTime.now().uptimeNanoseconds
        let packetMS = Double(sampleCount) / VBANPacket.sampleRate * 1000.0

        arrivalJitter.withLock { state in
            defer {
                state.lastArrivalNS = now
                state.lastFrameCounter = frame
            }

            guard let previousNS = state.lastArrivalNS,
                  let previousFrame = state.lastFrameCounter else {
                return
            }

            let frameDistance = frame &- previousFrame
            guard frameDistance > 0, frameDistance < 1_000 else {
                return
            }

            let actualMS = Double(now - previousNS) / 1_000_000.0
            let expectedMS = packetMS * Double(frameDistance)
            let deviationMS = min(abs(actualMS - expectedMS), 50.0)

            // RFC3550-style smoothing, plus a decaying short-term peak for burst jitter.
            state.smoothedDeviationMS +=
                (deviationMS - state.smoothedDeviationMS) / 16.0
            state.peakDeviationMS = max(
                deviationMS,
                state.peakDeviationMS * 0.94
            )
        }
    }

    private func frames(
        forMS ms: Double
    ) -> Int {
        Int(
            VBANPacket.sampleRate *
            ms /
            1000.0
        )
    }

    private func openSocket() throws {
        let fd = Darwin.socket(
            AF_INET,
            SOCK_DGRAM,
            IPPROTO_UDP
        )

        guard fd >= 0 else {
            throw VBANReceiverError
                .socketCreation
        }

        var reuse: Int32 = 1

        _ = withUnsafePointer(
            to: &reuse
        ) {
            setsockopt(
                fd,
                SOL_SOCKET,
                SO_REUSEADDR,
                $0,
                socklen_t(
                    MemoryLayout<Int32>.size
                )
            )
        }

        var receiveBuffer: Int32 =
            2_097_152

        _ = withUnsafePointer(
            to: &receiveBuffer
        ) {
            setsockopt(
                fd,
                SOL_SOCKET,
                SO_RCVBUF,
                $0,
                socklen_t(
                    MemoryLayout<Int32>.size
                )
            )
        }

        let flags =
            fcntl(
                fd,
                F_GETFL,
                0
            )

        _ = fcntl(
            fd,
            F_SETFL,
            flags | O_NONBLOCK
        )

        var address =
            sockaddr_in()

        address.sin_len =
            UInt8(
                MemoryLayout<
                    sockaddr_in
                >.size
            )

        address.sin_family =
            sa_family_t(AF_INET)

        address.sin_port =
            listenPort.bigEndian

        address.sin_addr =
            in_addr(
                s_addr: INADDR_ANY
            )

        let result: Int32 =
            withUnsafePointer(
                to: &address
            ) { pointer in
                pointer.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1
                ) {
                    Darwin.bind(
                        fd,
                        $0,
                        socklen_t(
                            MemoryLayout<
                                sockaddr_in
                            >.size
                        )
                    )
                }
            }

        guard result == 0 else {
            Darwin.close(fd)

            throw VBANReceiverError
                .bindFailed(
                    listenPort
                )
        }

        socketFD = fd

        let source =
            DispatchSource.makeReadSource(
                fileDescriptor: fd,
                queue: networkQueue
            )

        source.setEventHandler {
            [weak self] in
            self?.drainSocket()
        }

        source.setCancelHandler {}

        readSource = source
        source.resume()
    }

    private func drainSocket() {
        guard socketFD >= 0 else {
            return
        }

        var packet =
            [UInt8](
                repeating: 0,
                count: 2048
            )

        let capacity =
            packet.count

        while true {
            let count =
                packet
                    .withUnsafeMutableBytes {
                        buffer in

                        Darwin.recv(
                            socketFD,
                            buffer.baseAddress,
                            capacity,
                            0
                        )
                    }

            if count <= 0 {
                if errno == EAGAIN ||
                    errno == EWOULDBLOCK {
                    break
                }

                break
            }

            parsePacket(
                packet,
                count: count
            )
        }
    }

    private func parsePacket(
        _ bytes: [UInt8],
        count: Int
    ) {
        guard count >= 28 else {
            packetsRejected &+= 1
            return
        }

        guard
            bytes[0] == 0x56,
            bytes[1] == 0x42,
            bytes[2] == 0x41,
            bytes[3] == 0x4E
        else {
            packetsRejected &+= 1
            return
        }

        let sampleRateIndex =
            bytes[4] & 0x1F

        let sampleCount =
            Int(bytes[5]) + 1

        let channels =
            Int(bytes[6]) + 1

        let dataType =
            bytes[7] & 0x07

        guard
            sampleRateIndex ==
                VBANPacket.sampleRateIndex,
            dataType == 1,
            channels == 1 ||
                channels == 2,
            sampleCount > 0 &&
                sampleCount <= 256
        else {
            packetsRejected &+= 1
            return
        }

        let nameBytes =
            bytes[8..<24]

        let streamName =
            String(
                bytes:
                    nameBytes.prefix {
                        $0 != 0
                    },
                encoding: .ascii
            ) ?? ""

        guard
            streamName ==
                expectedStreamName
        else {
            return
        }

        let payloadBytes =
            sampleCount *
            channels *
            2

        guard
            count >=
                28 + payloadBytes
        else {
            packetsRejected &+= 1
            return
        }

        let frame =
            UInt32(bytes[24]) |
            UInt32(bytes[25]) << 8 |
            UInt32(bytes[26]) << 16 |
            UInt32(bytes[27]) << 24

        if let previous =
            lastFrameCounter {
            let expected =
                previous &+ 1

            if frame != expected {
                let delta =
                    frame &- expected

                if delta < 10_000 {
                    lostFrames &+=
                        UInt64(delta)
                }
            }
        }

        lastFrameCounter = frame
        recordPacketArrival(frame: frame, sampleCount: sampleCount)

        var offset = 28

        for index in 0..<sampleCount {
            let l = Int16(
                bitPattern:
                    UInt16(bytes[offset]) |
                    UInt16(bytes[offset + 1]) << 8
            )
            offset += 2

            let leftValue = Float(l) / Float(Int16.max)
            decodeLeft[index] = leftValue

            if channels == 2 {
                let r = Int16(
                    bitPattern:
                        UInt16(bytes[offset]) |
                        UInt16(bytes[offset + 1]) << 8
                )
                offset += 2
                decodeRight[index] = Float(r) / Float(Int16.max)
            } else {
                decodeRight[index] = leftValue
            }
        }

        ring.pushStereo(
            left: decodeLeft,
            right: decodeRight,
            frameCount: sampleCount
        )

        packetsReceived &+= 1
    }

    /// Called on networkQueue so packet counters and frame-loss accounting are read
    /// on the same serial queue that mutates them. Rate/target are captured by the
    /// control queue and passed by value to avoid cross-queue data races.
    private func publishDiagnostics(
        playbackRate: Float,
        targetMS: Double
    ) {
        let stats = ring.stats()

        onDiagnostics?(
            packetsReceived,
            packetsRejected,
            lostFrames,
            stats.bufferedFrames,
            stats.underflows,
            stats.primed,
            playbackRate,
            targetMS
        )
    }
}

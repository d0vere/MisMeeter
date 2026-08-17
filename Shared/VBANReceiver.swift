import AVFoundation
import Darwin
import Foundation

enum VBANReceiverError: LocalizedError {
    case socketCreation
    case bindFailed(UInt16)
    case audioFormat

    var errorDescription: String? {
        switch self {
        case .socketCreation:
            return "Could not create the VBAN receive UDP socket."
        case .bindFailed(let port):
            return "Could not bind UDP port \(port). It may already be in use."
        case .audioFormat:
            return "Could not create the 48 kHz stereo playback format."
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

    private var expectedStreamName = "MisMeeterRX"
    private var listenPort: UInt16 = 6980

    private var configuredBufferMS: Double = 100
    private var adaptiveTargetMS: Double = 100

    private var packetsReceived: UInt64 = 0
    private var packetsRejected: UInt64 = 0
    private var lastFrameCounter: UInt32?
    private var lostFrames: UInt64 = 0

    private var lastUnderflowCount: UInt64 = 0
    private var stableControlWindows = 0
    private var currentRate: Float = 1.0

    private(set) var isRunning = false

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

    func start(
        preset: VBANReceivePreset,
        transmitterAlreadyActive: Bool
    ) throws {
        stop(deactivateSession: false)

        expectedStreamName =
            preset.sanitizedStreamName

        listenPort = preset.port

        configuredBufferMS =
            max(40, min(300, preset.bufferMS))

        adaptiveTargetMS =
            configuredBufferMS

        ring.reset(
            targetFrames:
                frames(forMS: adaptiveTargetMS)
        )

        if !transmitterAlreadyActive {
            try AudioSessionCoordinator.shared
                .configureForDuplex(
                    voiceProcessing: false
                )
        } else {
            AudioSessionCoordinator.shared
                .forceSpeaker()
        }

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

        engine.prepare()
        try engine.start()

        AudioSessionCoordinator.shared
            .forceSpeaker()

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
                frames(forMS: 100)
        )

        if deactivateSession {
            AudioSessionCoordinator.shared
                .deactivateIfPossible()
        }

        onStatus?("Receiver stopped")
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
    /// v1.5 uses AVAudioUnitTimePitch so playback rate can be corrected
    /// more aggressively without intentionally shifting pitch. The servo
    /// keeps the jitter buffer near the selected/adaptive target.
    private func updateClockRecovery() {
        guard isRunning else { return }

        let stats = ring.stats()

        let targetFrames =
            max(
                256,
                ring.targetFrames()
            )

        let error =
            Double(
                stats.bufferedFrames -
                targetFrames
            ) /
            Double(targetFrames)

        // Dead-zone prevents constant tiny speed changes around target.
        let effectiveError: Double
        if abs(error) < 0.08 {
            effectiveError = 0
        } else {
            effectiveError = error
        }

        // Up to +/-2% when the buffer is badly displaced. Since TimePitch
        // preserves pitch, this is much less objectionable than Varispeed.
        let desiredRate =
            Float(
                max(
                    0.98,
                    min(
                        1.02,
                        1.0 + effectiveError * 0.015
                    )
                )
            )

        currentRate =
            currentRate * 0.82 +
            desiredRate * 0.18

        DispatchQueue.main.async { [weak self] in
            self?.timePitch?.rate =
                self?.currentRate ?? 1.0
        }

        let hadNewUnderflow =
            stats.underflows !=
            lastUnderflowCount

        if hadNewUnderflow {
            // Add 50 ms immediately after an underflow. This also
            // forces a genuine re-prime if the queue is below the new target.
            adaptiveTargetMS =
                min(
                    600,
                    adaptiveTargetMS + 50
                )

            ring.setTargetFrames(
                frames(
                    forMS:
                        adaptiveTargetMS
                )
            )

            stableControlWindows = 0
        } else if stats.primed {
            stableControlWindows += 1

            // After 30 s without underflow, slowly move back toward
            // the user's configured buffer.
            if stableControlWindows >= 60 &&
                adaptiveTargetMS >
                    configuredBufferMS {
                adaptiveTargetMS =
                    max(
                        configuredBufferMS,
                        adaptiveTargetMS - 10
                    )

                ring.setTargetFrames(
                    frames(
                        forMS:
                            adaptiveTargetMS
                    )
                )

                stableControlWindows = 0
            }
        } else {
            stableControlWindows = 0
        }

        lastUnderflowCount =
            stats.underflows

        publishDiagnostics()
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

        var left = [Float]()
        var right = [Float]()

        left.reserveCapacity(
            sampleCount
        )

        right.reserveCapacity(
            sampleCount
        )

        var offset = 28

        for _ in 0..<sampleCount {
            let l =
                Int16(
                    bitPattern:
                        UInt16(
                            bytes[offset]
                        ) |
                        UInt16(
                            bytes[
                                offset + 1
                            ]
                        ) << 8
                )

            offset += 2

            let lv =
                Float(l) /
                Float(Int16.max)

            if channels == 2 {
                let r =
                    Int16(
                        bitPattern:
                            UInt16(
                                bytes[
                                    offset
                                ]
                            ) |
                            UInt16(
                                bytes[
                                    offset + 1
                                ]
                            ) << 8
                    )

                offset += 2

                left.append(lv)

                right.append(
                    Float(r) /
                    Float(Int16.max)
                )
            } else {
                left.append(lv)
                right.append(lv)
            }
        }

        ring.pushStereo(
            left: left,
            right: right
        )

        packetsReceived &+= 1

        if packetsReceived % 64 == 0 {
            publishDiagnostics()
        }
    }

    private func publishDiagnostics() {
        let stats =
            ring.stats()

        onDiagnostics?(
            packetsReceived,
            packetsRejected,
            lostFrames,
            stats.bufferedFrames,
            stats.underflows,
            stats.primed,
            currentRate,
            adaptiveTargetMS
        )
    }
}

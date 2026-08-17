import AVFoundation
import Foundation
import AudioToolbox

enum MicrophoneEngineError: LocalizedError {
    case noInput
    case unsupportedSampleRate(Double)

    var errorDescription: String? {
        switch self {
        case .noInput:
            return "No microphone input is available."
        case .unsupportedSampleRate(let rate):
            return "The microphone is running at \(Int(rate)) Hz. MisMeeter currently requires 48000 Hz."
        }
    }
}

final class MicrophoneEngine {
    private let engine = AVAudioEngine()
    private let transmitter: VBANTransmitter
    private var sinkNode: AVAudioSinkNode?
    private var keepAliveSourceNode: AVAudioSourceNode?

    private let gainLock = NSLock()
    private var _gainDB: Float = 12

    var onMeter: ((Float) -> Void)?
    var onAudioDiagnostics: ((Int, Double) -> Void)?
    var onVoiceProcessingState: ((Bool) -> Void)?

    init(transmitter: VBANTransmitter) {
        self.transmitter = transmitter
    }

    var gainDB: Float {
        get {
            gainLock.lock()
            defer { gainLock.unlock() }
            return _gainDB
        }
        set {
            gainLock.lock()
            _gainDB = max(0, min(24, newValue))
            gainLock.unlock()
        }
    }

    func start(voiceProcessingEnabled: Bool, backgroundOutputKeepAlive: Bool = true) throws {
        // Apple requires the engine to be stopped before switching voice processing.
        if engine.isRunning {
            engine.stop()
        }

        if let oldSink = sinkNode {
            engine.disconnectNodeInput(oldSink)
            engine.detach(oldSink)
            sinkNode = nil
        }

        if let oldKeepAlive = keepAliveSourceNode {
            engine.disconnectNodeOutput(oldKeepAlive)
            engine.detach(oldKeepAlive)
            keepAliveSourceNode = nil
        }

        let session = AVAudioSession.sharedInstance()

        if voiceProcessingEnabled {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker]
            )
        } else {
            // playAndRecord keeps the output path available so the independent
            // VBAN receiver can play through the iPhone speaker while TX is active.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
        }

        try session.setPreferredSampleRate(VBANPacket.sampleRate)
        try session.setPreferredIOBufferDuration(
            VBANPacket.packetDurationSeconds
        )
        try session.setActive(true)

        guard session.isInputAvailable else {
            throw MicrophoneEngineError.noInput
        }

        let input = engine.inputNode

        // VoiceProcessingIO provides Apple's tuned speech processing:
        // noise suppression, echo cancellation and automatic gain processing.
        try input.setVoiceProcessingEnabled(voiceProcessingEnabled)
        onVoiceProcessingState?(input.isVoiceProcessingEnabled)

        let actualRate = session.sampleRate
        let actualDuration = session.ioBufferDuration

        guard abs(actualRate - VBANPacket.sampleRate) < 1 else {
            throw MicrophoneEngineError.unsupportedSampleRate(actualRate)
        }

        let format = input.outputFormat(forBus: 0)
        let commonFormat = format.commonFormat

        print(
            "MISMEETER: realtime sink: \(actualRate) Hz, " +
            "\(actualDuration * 1000) ms I/O, " +
            "voiceProcessing=\(input.isVoiceProcessingEnabled)"
        )

        let sink = AVAudioSinkNode { [weak self] _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }

            self.processRealtime(
                audioBufferList: audioBufferList,
                frameCount: Int(frameCount),
                commonFormat: commonFormat,
                actualIOBufferDuration: actualDuration
            )

            return noErr
        }

        sinkNode = sink
        engine.attach(sink)
        engine.connect(input, to: sink, format: format)

        if backgroundOutputKeepAlive {
            // Keep the output side of the hardware I/O graph actively rendering
            // while TX is running. The samples are exactly zero and this engine's
            // mixer is muted, so nothing is audible.
            let outputFormat = AVAudioFormat(
                standardFormatWithSampleRate: VBANPacket.sampleRate,
                channels: 2
            )!

            let silence = AVAudioSourceNode(
                format: outputFormat
            ) { _, _, frameCount, audioBufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(
                    audioBufferList
                )

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

            keepAliveSourceNode = silence
            engine.attach(silence)
            engine.connect(
                silence,
                to: engine.mainMixerNode,
                format: outputFormat
            )

            // Silence only this engine; the independent RX engine remains audible.
            engine.mainMixerNode.outputVolume = 0
        } else {
            engine.mainMixerNode.outputVolume = 1
        }

        engine.prepare()
        try engine.start()
    }

    func stop(deactivateSession: Bool = true) {
        engine.stop()

        if let sink = sinkNode {
            engine.disconnectNodeInput(sink)
            engine.detach(sink)
            sinkNode = nil
        }

        if let silence = keepAliveSourceNode {
            engine.disconnectNodeOutput(silence)
            engine.detach(silence)
            keepAliveSourceNode = nil
        }

        engine.mainMixerNode.outputVolume = 1

        if deactivateSession {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            } catch {
                print("MISMEETER: session deactivate error: \(error)")
            }
        }
    }

    private func processRealtime(
        audioBufferList: UnsafePointer<AudioBufferList>,
        frameCount: Int,
        commonFormat: AVAudioCommonFormat,
        actualIOBufferDuration: Double
    ) {
        guard frameCount > 0 else { return }

        // Built-in iPhone microphone is mono in this graph; use the first buffer.
        let audioBuffer = audioBufferList.pointee.mBuffers
        guard let data = audioBuffer.mData else { return }

        let currentGainDB = gainDB
        let linearGain = powf(10, currentGainDB / 20)

        var output = [Int16]()
        output.reserveCapacity(frameCount)

        var peak: Float = 0

        switch commonFormat {
        case .pcmFormatFloat32:
            let pointer = data.assumingMemoryBound(to: Float.self)

            for index in 0..<frameCount {
                let raw = pointer[index]
                peak = max(peak, abs(raw))

                let limited = tanhf(raw * linearGain)

                output.append(
                    Int16(
                        max(-1, min(1, limited))
                        * Float(Int16.max)
                    )
                )
            }

        case .pcmFormatInt16:
            let pointer = data.assumingMemoryBound(to: Int16.self)

            for index in 0..<frameCount {
                let raw = Float(pointer[index]) / Float(Int16.max)
                peak = max(peak, abs(raw))

                let limited = tanhf(raw * linearGain)

                output.append(
                    Int16(
                        max(-1, min(1, limited))
                        * Float(Int16.max)
                    )
                )
            }

        default:
            return
        }

        onMeter?(min(1, peak * linearGain))
        onAudioDiagnostics?(frameCount, actualIOBufferDuration)

        // The sink callback itself supplies the realtime cadence.
        // Network work stays on VBANTransmitter's serial queue.
        transmitter.enqueue(output)
    }
}

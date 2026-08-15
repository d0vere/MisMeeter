import AVFoundation
import Foundation

enum MicrophoneEngineError: LocalizedError {
    case noInput
    case unsupportedSampleRate(Double)

    var errorDescription: String? {
        switch self {
        case .noInput:
            return "No microphone input is available."
        case .unsupportedSampleRate(let rate):
            return "Active mic sample rate is \(Int(rate)) Hz; MisMeeter v0.3 requires 48000 Hz."
        }
    }
}

final class MicrophoneEngine {
    private let engine = AVAudioEngine()
    private let transmitter: VBANTransmitter

    var isMutedProvider: () -> Bool = { false }
    var onMeter: ((Float) -> Void)?

    init(transmitter: VBANTransmitter) {
        self.transmitter = transmitter
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setPreferredSampleRate(VBANPacket.sampleRate)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)

        guard session.isInputAvailable else {
            throw MicrophoneEngineError.noInput
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard abs(format.sampleRate - VBANPacket.sampleRate) < 1.0 else {
            throw MicrophoneEngineError.unsupportedSampleRate(format.sampleRate)
        }

        input.removeTap(onBus: 0)
        input.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(VBANPacket.samplesPerPacket),
            format: format
        ) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            print("MISMEETER: session deactivate error: \(error)")
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var output = [Int16]()
        output.reserveCapacity(frameCount)
        var peak: Float = 0

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channel = buffer.floatChannelData?[0] else { return }
            for i in 0..<frameCount {
                let v = max(-1.0, min(1.0, channel[i]))
                peak = max(peak, abs(v))
                output.append(Int16(v * Float(Int16.max)))
            }

        case .pcmFormatInt16:
            guard let channel = buffer.int16ChannelData?[0] else { return }
            for i in 0..<frameCount {
                let s = channel[i]
                peak = max(peak, abs(Float(s) / Float(Int16.max)))
                output.append(s)
            }

        default:
            return
        }

        onMeter?(peak)
        transmitter.enqueue(output, muted: isMutedProvider())
    }
}

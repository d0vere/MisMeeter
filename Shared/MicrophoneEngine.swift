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
            return "The microphone is running at \(Int(rate)) Hz. MisMeeter currently requires 48000 Hz."
        }
    }
}

final class MicrophoneEngine {
    private let engine = AVAudioEngine()
    private let transmitter: VBANTransmitter

    private let gainLock = NSLock()
    private var _gainDB: Float = 12

    var onMeter: ((Float) -> Void)?

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

    func start() throws {
        let session = AVAudioSession.sharedInstance()

        // `.measurement` intentionally minimizes processing and can sound
        // surprisingly quiet for speech. v0.4 uses the normal recording mode.
        try session.setCategory(
            .record,
            mode: .default,
            options: []
        )

        try session.setPreferredSampleRate(VBANPacket.sampleRate)

        // Match VBAN packet duration as closely as the hardware permits.
        try session.setPreferredIOBufferDuration(
            VBANPacket.packetDurationSeconds
        )

        try session.setActive(true)

        guard session.isInputAvailable else {
            throw MicrophoneEngineError.noInput
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard abs(format.sampleRate - VBANPacket.sampleRate) < 1 else {
            throw MicrophoneEngineError.unsupportedSampleRate(format.sampleRate)
        }

        input.removeTap(onBus: 0)

        input.installTap(
            onBus: 0,
            bufferSize: 1024,
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

        let currentGainDB = gainDB
        let linearGain = powf(10, currentGainDB / 20)

        var output = [Int16]()
        output.reserveCapacity(frameCount)

        var peak: Float = 0

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channels = buffer.floatChannelData else { return }
            let channel = channels[0]

            for index in 0..<frameCount {
                let raw = channel[index]
                peak = max(peak, abs(raw))

                let amplified = raw * linearGain

                // Soft saturation instead of a hard digital cliff.
                // For small signals this is effectively just gain.
                let limited = tanhf(amplified)

                output.append(
                    Int16(
                        max(-1, min(1, limited))
                        * Float(Int16.max)
                    )
                )
            }

        case .pcmFormatInt16:
            guard let channels = buffer.int16ChannelData else { return }
            let channel = channels[0]

            for index in 0..<frameCount {
                let raw = Float(channel[index]) / Float(Int16.max)
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
        transmitter.enqueue(output)
    }
}

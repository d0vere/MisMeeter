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
    var onAudioDiagnostics: ((Int, Double) -> Void)?

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

        try session.setCategory(
            .record,
            mode: .default,
            options: []
        )

        // Preferences must be requested before activation. They are hints:
        // after activation we inspect the actual values chosen by iOS.
        try session.setPreferredSampleRate(VBANPacket.sampleRate)
        try session.setPreferredIOBufferDuration(
            VBANPacket.packetDurationSeconds
        )

        try session.setActive(true)

        guard session.isInputAvailable else {
            throw MicrophoneEngineError.noInput
        }

        let actualRate = session.sampleRate
        let actualDuration = session.ioBufferDuration

        guard abs(actualRate - VBANPacket.sampleRate) < 1 else {
            throw MicrophoneEngineError.unsupportedSampleRate(actualRate)
        }

        print(
            "MISMEETER: actual audio session: \(actualRate) Hz, " +
            "\(actualDuration * 1000) ms I/O buffer"
        )

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)

        // 256 is a request, not a guarantee. If iOS hands us 512/1024 samples,
        // VBANTransmitter splits them into consecutive 256-sample packets.
        input.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(VBANPacket.samplesPerPacket),
            format: format
        ) { [weak self] buffer, _ in
            self?.process(
                buffer,
                actualIOBufferDuration: actualDuration
            )
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

    private func process(
        _ buffer: AVAudioPCMBuffer,
        actualIOBufferDuration: Double
    ) {
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

                let limited = tanhf(raw * linearGain)

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
        onAudioDiagnostics?(frameCount, actualIOBufferDuration)

        // No network work on the real-time audio callback:
        // enqueue() switches immediately onto the transmitter's serial queue.
        transmitter.enqueue(output)
    }
}

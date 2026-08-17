import AVFoundation
import Foundation

final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private init() {}

    func configureForDuplex(
        voiceProcessing: Bool
    ) throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: voiceProcessing ? .voiceChat : .default,
            options: [.defaultToSpeaker]
        )

        try session.setPreferredSampleRate(
            VBANPacket.sampleRate
        )

        try session.setPreferredIOBufferDuration(
            VBANPacket.packetDurationSeconds
        )

        try session.setActive(true)

        // Explicitly force loudspeaker while the app owns a playAndRecord
        // session. This avoids iOS reverting output to the built-in receiver
        // when TX and RX become active together.
        try? session.overrideOutputAudioPort(.speaker)
    }

    func forceSpeaker() {
        let session = AVAudioSession.sharedInstance()

        guard session.category == .playAndRecord else {
            return
        }

        try? session.overrideOutputAudioPort(.speaker)
    }

    func deactivateIfPossible() {
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

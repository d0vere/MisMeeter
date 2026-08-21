import AVFoundation
import Foundation

final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()
    private init() {}

    func configureForDuplex(voiceProcessing: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: voiceProcessing ? .voiceChat : .default,
            options: [.defaultToSpeaker]
        )
        try session.setPreferredSampleRate(VBANPacket.sampleRate)
        try session.setPreferredIOBufferDuration(VBANPacket.packetDurationSeconds)
        try session.setActive(true)
        try? session.overrideOutputAudioPort(.speaker)
    }

    /// Reasserts the already-configured audio session after an interruption or before
    /// promoting Now Playing. Keeping the category non-mixable while local controls
    /// are active is important for Now Playing eligibility on iOS.
    func ensureActive() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try session.setPreferredSampleRate(VBANPacket.sampleRate)
            try session.setPreferredIOBufferDuration(VBANPacket.packetDurationSeconds)
        }
        try session.setActive(true)
        try? session.overrideOutputAudioPort(.speaker)
    }

    func forceSpeaker() {
        let session = AVAudioSession.sharedInstance()
        guard session.category == .playAndRecord else { return }
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

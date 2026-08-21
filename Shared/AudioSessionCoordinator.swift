import AVFoundation
import Foundation

/// Owns AVAudioSession policy for the whole process.
///
/// RX-only deliberately uses `.playback`: there is no reason to keep an input
/// route open when MisMeeter is only listening, and `.playback` gives iOS the
/// most direct speaker playback path. As soon as TX is active we switch to
/// `.playAndRecord` with `.defaultToSpeaker` for true duplex operation.
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()
    private init() {}

    func configureForReceiveOnly() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback || session.mode != .default {
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try configureTiming(session)
        try session.setActive(true)
    }

    func configureForDuplex(voiceProcessing: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: voiceProcessing ? .voiceChat : .default,
            options: [.defaultToSpeaker]
        )
        try configureTiming(session)
        try session.setActive(true)
        try? session.overrideOutputAudioPort(.speaker)
    }

    /// Reassert the appropriate session policy after a route/configuration change.
    func ensureReceivePlayback(transmitterActive: Bool) throws {
        if transmitterActive {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker]
                )
                try configureTiming(session)
            }
            try session.setActive(true)
            try? session.overrideOutputAudioPort(.speaker)
        } else {
            try configureForReceiveOnly()
        }
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

    private func configureTiming(_ session: AVAudioSession) throws {
        try session.setPreferredSampleRate(VBANPacket.sampleRate)
        try session.setPreferredIOBufferDuration(VBANPacket.packetDurationSeconds)
    }
}

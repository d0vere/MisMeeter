import AVFoundation
import Foundation
import os

/// Owns and serializes AVAudioSession policy for the whole process.
///
/// RX-only deliberately uses `.playback`: there is no reason to keep an input
/// route open when MisMeeter is only listening. As soon as TX is active we switch
/// to `.playAndRecord` with `.defaultToSpeaker` for true duplex operation.
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private let lock = NSLock()
    private let logger = Logger(subsystem: "dev.mismeeter.app", category: "AudioSession")

    private init() {}

    func configureForDuplex(voiceProcessing: Bool) throws {
        try withSessionLock {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: voiceProcessing ? .voiceChat : .default,
                options: [.defaultToSpeaker]
            )
            try configureTiming(session)
            try session.setActive(true)
            preferBuiltInSpeakerIfNeeded(session)
        }
    }

    /// Reassert the appropriate session policy after a route/configuration change.
    func ensureReceivePlayback(transmitterActive: Bool) throws {
        try withSessionLock {
            let session = AVAudioSession.sharedInstance()
            if transmitterActive {
                if session.category != .playAndRecord {
                    try session.setCategory(
                        .playAndRecord,
                        mode: .default,
                        options: [.defaultToSpeaker]
                    )
                }
                // Route changes can invalidate preferred hardware timing even when
                // the category itself is unchanged.
                try configureTiming(session)
                try session.setActive(true)
                preferBuiltInSpeakerIfNeeded(session)
            } else {
                try configureReceiveOnly(session)
            }
        }
    }

    /// `.defaultToSpeaker` is the normal policy. Only force the speaker when iOS
    /// has actually fallen back to the built-in receiver; never override an
    /// external route such as Bluetooth, CarPlay, AirPlay, USB or headphones.
    func preferBuiltInSpeakerIfNeeded() {
        withSessionLock {
            preferBuiltInSpeakerIfNeeded(AVAudioSession.sharedInstance())
        }
    }

    func deactivateIfPossible() {
        withSessionLock {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            } catch {
                logger.error("Audio session deactivation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func configureReceiveOnly(_ session: AVAudioSession) throws {
        if session.category != .playback || session.mode != .default {
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try configureTiming(session)
        try session.setActive(true)
    }

    private func preferBuiltInSpeakerIfNeeded(_ session: AVAudioSession) {
        guard session.category == .playAndRecord,
              session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver })
        else {
            return
        }
        do {
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            logger.debug("Speaker override skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func configureTiming(_ session: AVAudioSession) throws {
        try session.setPreferredSampleRate(VBANPacket.sampleRate)
        try session.setPreferredIOBufferDuration(VBANPacket.packetDurationSeconds)
    }

    @discardableResult
    private func withSessionLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

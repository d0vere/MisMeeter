import AppIntents
import WidgetKit

/// Dedicated Control Center / Lock Screen action.
///
/// This is intentionally a plain AppIntent rather than a LiveActivityIntent: the
/// control and the Live Activity are two different system surfaces and should not
/// share execution semantics. The runtime snapshot remains the source of truth.
struct ToggleMicrophoneControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle TX Microphone"
    static var description = IntentDescription("Mute or unmute the active MisMeeter microphone transmission.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        let snapshot = SharedAppState.readSnapshot()
        guard snapshot.isStreaming else {
            ControlCenter.shared.reloadControls(ofKind: SharedAppState.ControlKinds.microphone)
            return .result()
        }

        let desiredMuted = !snapshot.isMuted
        SharedAppState.issue(.setMicrophoneMuted, value: desiredMuted)

        await SharedAppState.waitForSnapshot(timeoutMilliseconds: 900) { updated in
            updated.isStreaming && updated.isMuted == desiredMuted
        }

        ControlCenter.shared.reloadControls(ofKind: SharedAppState.ControlKinds.microphone)
        return .result()
    }
}

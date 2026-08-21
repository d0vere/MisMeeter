import AppIntents
import WidgetKit

/// Live Activity toggle that derives the requested value from the latest shared
/// runtime snapshot and waits for the runtime to publish the applied state.
struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Microphone"
    static var description = IntentDescription("Mute or unmute the active MisMeeter microphone transmission.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        let snapshot = SharedAppState.readSnapshot()
        guard snapshot.isStreaming else { return .result() }

        let desiredMuted = !snapshot.isMuted
        SharedAppState.issue(.setMicrophoneMuted, value: desiredMuted)
        await SharedAppState.waitForSnapshot(timeoutMilliseconds: 650) { updated in
            updated.isStreaming && updated.isMuted == desiredMuted
        }

        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: SharedAppState.ControlKinds.microphone)
        }
        return .result()
    }
}

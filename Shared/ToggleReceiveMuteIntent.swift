import AppIntents
import WidgetKit

/// Live Activity RX toggle that asks the running audio engine for one exact target
/// value instead of publishing speculative state from the extension process.
struct ToggleReceiveMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Receive Audio"
    static var description = IntentDescription("Mute or unmute MisMeeter receive playback while keeping the receiver synchronized.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        let snapshot = SharedAppState.readSnapshot()
        guard snapshot.isReceiving else { return .result() }

        let desiredMuted = !snapshot.isReceiveMuted
        SharedAppState.issue(.setReceiveMuted, value: desiredMuted)
        await SharedAppState.waitForSnapshot(timeoutMilliseconds: 650) { updated in
            updated.isReceiving && updated.isReceiveMuted == desiredMuted
        }

        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: SharedAppState.ControlKinds.receive)
        }
        return .result()
    }
}

import AppIntents
import WidgetKit

/// Dedicated Control Center / Lock Screen action for RX output mute.
struct ToggleReceiveControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle RX Audio"
    static var description = IntentDescription("Mute or unmute active MisMeeter receive playback.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        let snapshot = SharedAppState.readSnapshot()
        guard snapshot.isReceiving else {
            ControlCenter.shared.reloadControls(ofKind: SharedAppState.ControlKinds.receive)
            return .result()
        }

        let desiredMuted = !snapshot.isReceiveMuted
        SharedAppState.issue(.setReceiveMuted, value: desiredMuted)

        await SharedAppState.waitForSnapshot(timeoutMilliseconds: 900) { updated in
            updated.isReceiving && updated.isReceiveMuted == desiredMuted
        }

        ControlCenter.shared.reloadControls(ofKind: SharedAppState.ControlKinds.receive)
        return .result()
    }
}

import AppIntents
import WidgetKit

/// Exact-value intent used by the iOS Control Center / Lock Screen toggle.
/// `value == true` means received VBAN audio should be audible (unmuted).
/// The runtime owns the truth; the extension only requests a target value and then
/// asks the system to re-read the resulting shared state.
struct SetReceiveEnabledIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Receive Audio"
    static var description = IntentDescription("Enable or mute MisMeeter receive playback.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Receive audio enabled")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let snapshot = SharedAppState.readSnapshot()
        guard snapshot.isReceiving else { return .result() }

        let desiredMuted = !value
        SharedAppState.issue(.setReceiveMuted, value: desiredMuted)

        await SharedAppState.waitForSnapshot(timeoutMilliseconds: 650) { updated in
            updated.isReceiving && updated.isReceiveMuted == desiredMuted
        }
        return .result()
    }
}

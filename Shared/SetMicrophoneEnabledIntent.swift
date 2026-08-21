import AppIntents
import WidgetKit

/// Exact-value intent used by the iOS Control Center / Lock Screen toggle.
/// `value == true` means microphone transmission should be enabled (unmuted).
/// The shared snapshot remains runtime-authoritative: this intent never paints an
/// optimistic state that the audio engine has not actually applied.
struct SetMicrophoneEnabledIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Microphone"
    static var description = IntentDescription("Enable or mute the active MisMeeter microphone transmission.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Microphone enabled")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let snapshot = SharedAppState.readSnapshot()
        guard snapshot.isStreaming else { return .result() }

        let desiredMuted = !value
        SharedAppState.issue(.setMicrophoneMuted, value: desiredMuted)

        // Give the already-running audio runtime a short opportunity to acknowledge
        // the exact value by publishing a fresh snapshot. If it cannot, the control
        // deliberately re-renders the previous real state instead of lying to the UI.
        await SharedAppState.waitForSnapshot(timeoutMilliseconds: 650) { updated in
            updated.isStreaming && updated.isMuted == desiredMuted
        }
        return .result()
    }
}

import AppIntents

/// Live Activity RX toggle. Execution occurs in the app process so no shared-state
/// read is needed to decide the next value.
struct ToggleReceiveMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Receive Audio"
    static var description = IntentDescription("Mute or unmute MisMeeter receive playback while keeping the receiver synchronized.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        #if MISMEETER_APP
        _ = MisMeeterRuntime.shared.toggleReceiveMuted()
        #endif
        return .result()
    }
}

import AppIntents

/// Live Activity microphone toggle. Because this is a LiveActivityIntent, iOS runs
/// it in the app process; the UI therefore toggles the actual audio runtime directly.
struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Microphone"
    static var description = IntentDescription("Mute or unmute the active MisMeeter microphone transmission.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        #if MISMEETER_APP
        _ = MisMeeterRuntime.shared.toggleMuted()
        #endif
        return .result()
    }
}

import AppIntents

/// Stops the authoritative runtime and lets MisMeeterRuntime end its own Live Activity.
struct EndLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop All"
    static var description = IntentDescription("Stops both MisMeeter transmission and reception and closes the Live Activity.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        #if MISMEETER_APP
        await MisMeeterRuntime.shared.stopAll()
        #endif
        return .result()
    }
}

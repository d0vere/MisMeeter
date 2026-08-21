import AppIntents

/// Native Control Center / Lock Screen mute switch for the active TX microphone.
///
/// `LiveActivityIntent` is intentional: Apple runs these intents in the app process,
/// so the control reaches the one authoritative MisMeeterRuntime directly instead of
/// trying to control audio through an extension-process mailbox.
struct SetMicrophoneMuteControlIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute TX Microphone"
    static var description = IntentDescription("Mute or unmute the active MisMeeter microphone transmission.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Microphone muted")
    var value: Bool

    func perform() async throws -> some IntentResult {
        #if MISMEETER_APP
        let runtime = MisMeeterRuntime.shared
        if runtime.isStreaming {
            runtime.setMuted(value)
        }
        #endif
        return .result()
    }
}

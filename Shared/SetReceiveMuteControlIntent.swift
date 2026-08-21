import AppIntents

/// Native Control Center / Lock Screen mute switch for active RX playback.
///
/// The system supplies the desired mute value. Conforming to `LiveActivityIntent`
/// forces execution into the app process, where the running VBAN receiver lives.
struct SetReceiveMuteControlIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute RX Audio"
    static var description = IntentDescription("Mute or unmute active MisMeeter receive playback.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "RX muted")
    var value: Bool

    func perform() async throws -> some IntentResult {
        #if MISMEETER_APP
        let runtime = MisMeeterRuntime.shared
        if runtime.isReceiving {
            runtime.setReceiveMuted(value)
        }
        #endif
        return .result()
    }
}

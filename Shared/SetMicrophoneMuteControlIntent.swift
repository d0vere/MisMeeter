import AppIntents

/// Native iOS 18 Control Center / Lock Screen toggle for TX mute.
///
/// This follows Apple's WWDC24 control pattern exactly: SetValueIntent supplies
/// the final Boolean state, and LiveActivityIntent moves execution into the app
/// process without opening the UI. The runtime persists the new control state
/// before perform() returns; WidgetKit then reloads the control automatically.
struct SetMicrophoneMuteControlIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute TX Microphone"
    static var description = IntentDescription(
        "Mute or unmute the active MisMeeter microphone transmission."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Microphone muted")
    var value: Bool

    func perform() async throws -> some IntentResult {
        #if MISMEETER_APP
        await MisMeeterRuntime.shared.setMutedFromSystemControl(value)
        #endif
        return .result()
    }
}

import AppIntents

/// Native iOS 18 Control Center / Lock Screen toggle for RX mute.
/// See SetMicrophoneMuteControlIntent for the execution/state model.
struct SetReceiveMuteControlIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute RX Audio"
    static var description = IntentDescription(
        "Mute or unmute active MisMeeter receive playback."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "RX muted")
    var value: Bool

    func perform() async throws -> some IntentResult {
        #if MISMEETER_APP
        await MisMeeterRuntime.shared.setReceiveMutedFromSystemControl(value)
        #endif
        return .result()
    }
}

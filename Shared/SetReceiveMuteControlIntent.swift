import AppIntents
import os

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
        let logger = Logger(subsystem: "dev.mismeeter.app", category: "ControlIntent")
        logger.info("RX control requested muted=\(value, privacy: .public)")
        await MisMeeterRuntime.shared.setReceiveMutedFromSystemControl(value)
        guard let persisted = SharedAppState.readSnapshotIfAvailable(), persisted.isReceiveMuted == value else {
            logger.error("RX control persistence verification failed")
            throw ControlIntentPersistenceError()
        }
        logger.info("RX control completed; persisted muted=\(persisted.isReceiveMuted, privacy: .public)")
        #endif
        return .result()
    }
}

private struct ControlIntentPersistenceError: LocalizedError {
    var errorDescription: String? { "MisMeeter could not persist the Control Center state" }
}

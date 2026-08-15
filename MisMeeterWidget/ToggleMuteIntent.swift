import ActivityKit
import AppIntents

struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute or unmute microphone"
    static var description = IntentDescription("Toggles the MisMeeter microphone state.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        for activity in Activity<MicActivityAttributes>.activities {
            let oldState = activity.content.state
            let newState = MicActivityAttributes.ContentState(
                isMuted: !oldState.isMuted,
                connectionLabel: oldState.connectionLabel
            )

            await activity.update(
                ActivityContent(state: newState, staleDate: nil)
            )
        }

        return .result()
    }
}

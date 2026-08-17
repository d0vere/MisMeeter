import ActivityKit
import AppIntents

struct EndLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop All"
    static var description = IntentDescription("Stops both MisMeeter transmission and reception and closes the Live Activity.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        SharedAppState.writeSnapshot(.idle)
        SharedAppState.issue(.stopAll)

        let state = MicActivityAttributes.ContentState(snapshot: .idle)
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        return .result()
    }
}

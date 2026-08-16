import ActivityKit
import AppIntents

struct EndLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End MisMeeter"
    static var description = IntentDescription(
        "Ends the MisMeeter Live Activity."
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let finalState = MicActivityAttributes.ContentState(
            isMuted: true,
            isStreaming: false,
            destinationLabel: "Stopped",
            presetLabel: "Stopped"
        )

        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(
                    state: finalState,
                    staleDate: nil
                ),
                dismissalPolicy: .immediate
            )
        }

        return .result()
    }
}

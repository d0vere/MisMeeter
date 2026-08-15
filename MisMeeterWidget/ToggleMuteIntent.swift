import ActivityKit
import AppIntents

struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle microphone"
    static var description = IntentDescription("Mute or unmute MisMeeter.")

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        print("MISMEETER: ToggleMuteIntent perform()")

        let activities = Activity<MicActivityAttributes>.activities

        print("MISMEETER: activities found = \(activities.count)")

        for activity in activities {
            let current = activity.content.state

            print("MISMEETER: current isMuted = \(current.isMuted)")

            let updated = MicActivityAttributes.ContentState(
                isMuted: !current.isMuted,
                connectionLabel: current.connectionLabel
            )

            await activity.update(
                ActivityContent(
                    state: updated,
                    staleDate: nil
                )
            )

            print("MISMEETER: updated isMuted = \(updated.isMuted)")
        }

        return .result()
    }
}

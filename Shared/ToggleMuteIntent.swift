import ActivityKit
import AppIntents
import Foundation

struct ToggleMuteIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Toggle Microphone"

    static var description = IntentDescription(
        "Mute or unmute the MisMeeter microphone."
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {

        print("====================================")
        print("MISMEETER: ToggleMuteIntent called")
        print("====================================")

        let activities = Activity<MicActivityAttributes>.activities

        print("MISMEETER: activities found: \(activities.count)")

        for activity in activities {

            let currentState = activity.content.state

            print(
                "MISMEETER: current muted state:",
                currentState.isMuted
            )

            let newState = MicActivityAttributes.ContentState(
                isMuted: !currentState.isMuted,
                connectionLabel: currentState.connectionLabel
            )

            let newContent = ActivityContent(
                state: newState,
                staleDate: nil
            )

            await activity.update(newContent)

            print(
                "MISMEETER: new muted state:",
                newState.isMuted
            )
        }

        return .result()
    }
}

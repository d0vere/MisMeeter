import ActivityKit
import AppIntents
import WidgetKit

struct EndLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop All"
    static var description = IntentDescription("Stops both MisMeeter transmission and reception and closes the Live Activity.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        let snapshot = SharedAppState.readSnapshot()
        guard snapshot.isStreaming || snapshot.isReceiving else {
            await endOrphanedActivities()
            reloadControls()
            return .result()
        }

        SharedAppState.issue(.stopAll)
        let stopped = await SharedAppState.waitForSnapshot(timeoutMilliseconds: 900) { updated in
            !updated.isStreaming && !updated.isReceiving
        }

        // Only dismiss the Live Activity after the runtime confirms that both
        // transports are stopped. Otherwise preserve the truthful system UI.
        if stopped {
            await endOrphanedActivities()
        }
        reloadControls()
        return .result()
    }

    private func endOrphanedActivities() async {
        let state = MicActivityAttributes.ContentState(snapshot: .idle)
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private func reloadControls() {
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }
}

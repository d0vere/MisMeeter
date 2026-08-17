import ActivityKit
import AppIntents

struct EndLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Transmission"
    static var description = IntentDescription("Stops the active MisMeeter microphone transmission.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        var snapshot = SharedAppState.readSnapshot()
        snapshot.isStreaming = false
        snapshot.isMuted = true
        snapshot.status = "Stopping…"
        SharedAppState.writeSnapshot(snapshot)
        SharedAppState.issue(.stopStreaming)

        let state = MicActivityAttributes.ContentState(
            isMuted: true,
            isStreaming: false,
            isReceiving: snapshot.isReceiving,
            destinationLabel: snapshot.destination,
            presetLabel: snapshot.presetName,
            startedAt: snapshot.startedAt,
            statusLabel: "Stopped"
        )
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        return .result()
    }
}

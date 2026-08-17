import ActivityKit
import AppIntents

struct ToggleReceiveMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Receive Audio"
    static var description = IntentDescription("Mute or unmute MisMeeter receive playback while keeping the receiver synchronized.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        var snapshot = SharedAppState.readSnapshot()
        guard snapshot.isReceiving else { return .result() }

        snapshot.isReceiveMuted.toggle()
        snapshot.status = snapshot.isReceiveMuted ? "Receive muted" : (snapshot.isStreaming ? "Duplex live" : "Listening")
        SharedAppState.writeSnapshot(snapshot)
        SharedAppState.issue(.toggleReceiveMute)

        let state = MicActivityAttributes.ContentState(snapshot: snapshot)
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        return .result()
    }
}

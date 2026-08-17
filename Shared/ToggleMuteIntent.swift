import ActivityKit
import AppIntents

struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Microphone"
    static var description = IntentDescription("Mute or unmute the active MisMeeter microphone transmission.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        var snapshot = SharedAppState.readSnapshot()
        guard snapshot.isStreaming else { return .result() }

        snapshot.isMuted.toggle()
        snapshot.status = snapshot.isMuted ? "Microphone muted" : (snapshot.isReceiving ? "Duplex live" : "Live")
        SharedAppState.writeSnapshot(snapshot)
        SharedAppState.issue(.toggleMicrophoneMute)

        let state = MicActivityAttributes.ContentState(snapshot: snapshot)
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        return .result()
    }
}

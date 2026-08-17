import ActivityKit
import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Microphone"
    static var description = IntentDescription("Mute or unmute the active MisMeeter transmission.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        var snapshot = SharedAppState.readSnapshot()
        guard snapshot.isStreaming else { return .result() }

        snapshot.isMuted.toggle()
        SharedAppState.writeSnapshot(snapshot)
        SharedAppState.issue(.toggleMute)

        let state = MicActivityAttributes.ContentState(
            isMuted: snapshot.isMuted,
            isStreaming: snapshot.isStreaming,
            isReceiving: snapshot.isReceiving,
            destinationLabel: snapshot.destination,
            presetLabel: snapshot.presetName,
            startedAt: snapshot.startedAt,
            statusLabel: snapshot.isMuted ? "Muted" : "Live"
        )
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        return .result()
    }
}

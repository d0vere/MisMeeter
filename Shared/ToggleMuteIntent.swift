import AppIntents
import Foundation

struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Microphone"
    static var description = IntentDescription("Mute or unmute MisMeeter.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let newMuted = MisMeeterRuntime.shared.toggleMuted()
        print("MISMEETER: LiveActivityIntent -> muted=\(newMuted)")

        await MisMeeterRuntime.shared.syncLiveActivity()
        return .result()
    }
}

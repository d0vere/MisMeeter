import AppIntents
import SwiftUI
import WidgetKit

/// iOS 18 system Controls for MisMeeter.
///
/// Important: these are intentionally `StaticControlConfiguration`s with no
/// `ControlValueProvider`. Whenever iOS reloads the control, WidgetKit rebuilds this
/// body in the widget-extension process and reads the same atomic `SharedAppState`
/// snapshot used by the rest of MisMeeter. That mirrors Apple's WWDC24 static-toggle
/// pattern and avoids a second provider/cache layer.
@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        let snapshot = SharedAppState.readSnapshot()
        let active = snapshot.isStreaming
        let muted = active && snapshot.isMuted

        return StaticControlConfiguration(kind: SharedControlStateStore.Kinds.microphone) {
            ControlWidgetToggle(
                "MisMeeter TX",
                isOn: muted,
                action: SetMicrophoneMuteControlIntent()
            ) { isMuted in
                Label(
                    active ? (isMuted ? "TX MUTED" : "TX ACTIVE") : "TX IDLE",
                    systemImage: txSymbol(active: active, muted: active && isMuted)
                )
                .controlWidgetStatus(
                    active
                        ? (isMuted ? "TX microphone muted" : "TX microphone active")
                        : "TX is not running"
                )
                .controlWidgetActionHint(
                    active
                        ? (isMuted ? "Unmute TX" : "Mute TX")
                        : "No active TX session"
                )
            }
            // ON means muted, matching the native Silent Mode visual language.
            .tint(.red)
        }
        .displayName("MisMeeter TX Mute")
        .description("Mute or unmute MisMeeter microphone transmission.")
    }

    private func txSymbol(active: Bool, muted: Bool) -> String {
        guard active else { return "mic" }
        return muted ? "mic.slash.fill" : "mic.fill"
    }
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterReceiveMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        let snapshot = SharedAppState.readSnapshot()
        let active = snapshot.isReceiving
        let muted = active && snapshot.isReceiveMuted

        return StaticControlConfiguration(kind: SharedControlStateStore.Kinds.receive) {
            ControlWidgetToggle(
                "MisMeeter RX",
                isOn: muted,
                action: SetReceiveMuteControlIntent()
            ) { isMuted in
                Label(
                    active ? (isMuted ? "RX MUTED" : "RX ACTIVE") : "RX IDLE",
                    systemImage: rxSymbol(active: active, muted: active && isMuted)
                )
                .controlWidgetStatus(
                    active
                        ? (isMuted ? "RX audio muted" : "RX audio active")
                        : "RX is not running"
                )
                .controlWidgetActionHint(
                    active
                        ? (isMuted ? "Unmute RX" : "Mute RX")
                        : "No active RX session"
                )
            }
            .tint(.red)
        }
        .displayName("MisMeeter RX Mute")
        .description("Mute or unmute MisMeeter receive playback.")
    }

    private func rxSymbol(active: Bool, muted: Bool) -> String {
        guard active else { return "speaker" }
        return muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }
}

import AppIntents
import SwiftUI
import WidgetKit

/// MisMeeter v4 deliberately models each system Control as one Boolean: MUTE.
/// This mirrors Apple's WWDC24 ControlWidgetToggle example as closely as possible.
///
/// - `false` = audio path is not muted (normal symbol, neutral system appearance)
/// - `true`  = mute is engaged (red tint, slashed symbol, highlighted toggle)
///
/// Transport running/idle metadata is intentionally not part of the toggle value.
/// A stale transport-status callback must never be able to freeze or invert a mute
/// control. The authoritative mute value is published synchronously by the app to
/// the dedicated App Group control-state file before the SetValueIntent returns.
@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedControlStateStore.Kinds.microphone,
            provider: Provider()
        ) { isMuted in
            ControlWidgetToggle(
                "MisMeeter TX",
                isOn: isMuted,
                action: SetMicrophoneMuteControlIntent()
            ) { newValue in
                Label(
                    newValue ? "TX MUTED" : "TX AUDIO",
                    systemImage: newValue ? "mic.slash.fill" : "mic.fill"
                )
                .controlWidgetStatus(newValue ? "TX microphone muted" : "TX microphone unmuted")
                .controlWidgetActionHint(newValue ? "Unmute TX" : "Mute TX")
            }
            // ON == muted. The system highlights the ON state using this tint,
            // matching the visual language of iOS's own mute/silent controls.
            .tint(.red)
        }
        .displayName("MisMeeter TX Mute")
        .description("Mute or unmute MisMeeter microphone transmission.")
    }

    struct Provider: ControlValueProvider {
        let previewValue = false

        func currentValue() async throws -> Bool {
            SharedControlStateStore.read().txMuted
        }
    }
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterReceiveMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedControlStateStore.Kinds.receive,
            provider: Provider()
        ) { isMuted in
            ControlWidgetToggle(
                "MisMeeter RX",
                isOn: isMuted,
                action: SetReceiveMuteControlIntent()
            ) { newValue in
                Label(
                    newValue ? "RX MUTED" : "RX AUDIO",
                    systemImage: newValue ? "speaker.slash.fill" : "speaker.wave.3.fill"
                )
                .controlWidgetStatus(newValue ? "RX audio muted" : "RX audio unmuted")
                .controlWidgetActionHint(newValue ? "Unmute RX" : "Mute RX")
            }
            .tint(.red)
        }
        .displayName("MisMeeter RX Mute")
        .description("Mute or unmute MisMeeter receive playback.")
    }

    struct Provider: ControlValueProvider {
        let previewValue = false

        func currentValue() async throws -> Bool {
            SharedControlStateStore.read().rxMuted
        }
    }
}

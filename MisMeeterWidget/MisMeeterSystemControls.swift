import AppIntents
import SwiftUI
import WidgetKit

/// The value rendered by a system Control.
///
/// `isOn` alone is not sufficient for MisMeeter because the label also needs to
/// know whether the corresponding transport is actually running. The transport bit
/// is presentation-only: it must never disable the Control, because a stale provider
/// snapshot must not suppress delivery of the SetValueIntent.
struct MisMeeterControlValue: Hashable, Sendable {
    let isActive: Bool
    let isMuted: Bool

    init(isActive: Bool, isMuted: Bool) {
        self.isActive = isActive
        self.isMuted = isActive && isMuted
    }
}

/// iOS 18 system Controls for MisMeeter.
///
/// MisMeeter uses a `ControlValueProvider` so WidgetKit can fetch the latest
/// cross-process App Group snapshot when rendering the control. The provider reads
/// the same atomic state used by the app, widgets and Live Activity, so there is no
/// second Control-specific cache.
@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    struct Provider: ControlValueProvider {
        let previewValue = false
        func currentValue() async throws -> Bool {
            let snapshot = SharedAppState.readSnapshot()
            return SharedAppState.controlMuted(.tx, fallback: snapshot.isMuted)
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SharedControlStateStore.Kinds.microphone, provider: Provider()) { muted in
            ControlWidgetToggle("MisMeeter TX", isOn: muted, action: SetMicrophoneMuteControlIntent()) { value in
                Label(value ? "TX MUTED" : "TX ACTIVE", systemImage: value ? "mic.slash.fill" : "mic.fill")
                    .controlWidgetStatus(value ? "TX microphone muted" : "TX microphone active")
                    .controlWidgetActionHint(value ? "Unmute TX" : "Mute TX")
            }
            .tint(.red)
        }
        .displayName("MisMeeter TX Mute")
        .description("Mute or unmute MisMeeter microphone transmission.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterReceiveMuteControl: ControlWidget {
    struct Provider: ControlValueProvider {
        let previewValue = false
        func currentValue() async throws -> Bool {
            let snapshot = SharedAppState.readSnapshot()
            return SharedAppState.controlMuted(.rx, fallback: snapshot.isReceiveMuted)
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SharedControlStateStore.Kinds.receive, provider: Provider()) { muted in
            ControlWidgetToggle("MisMeeter RX", isOn: muted, action: SetReceiveMuteControlIntent()) { value in
                Label(value ? "RX MUTED" : "RX ACTIVE", systemImage: value ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .controlWidgetStatus(value ? "RX audio muted" : "RX audio active")
                    .controlWidgetActionHint(value ? "Unmute RX" : "Mute RX")
            }
            .tint(.red)
        }
        .displayName("MisMeeter RX Mute")
        .description("Mute or unmute MisMeeter receive playback.")
    }
}

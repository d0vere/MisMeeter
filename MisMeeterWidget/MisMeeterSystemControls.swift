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
        var previewValue: MisMeeterControlValue {
            MisMeeterControlValue(isActive: false, isMuted: false)
        }

        func currentValue() async throws -> MisMeeterControlValue {
            let snapshot = SharedAppState.readSnapshot()
            return MisMeeterControlValue(
                isActive: snapshot.isStreaming,
                isMuted: snapshot.isMuted
            )
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedControlStateStore.Kinds.microphone,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "MisMeeter TX",
                isOn: value.isMuted,
                action: SetMicrophoneMuteControlIntent()
            ) { isMuted in
                Label(
                    value.isActive ? (isMuted ? "TX MUTED" : "TX ACTIVE") : "TX IDLE",
                    systemImage: txSymbol(
                        active: value.isActive,
                        muted: value.isActive && isMuted
                    )
                )
                .controlWidgetStatus(
                    value.isActive
                        ? (isMuted ? "TX microphone muted" : "TX microphone active")
                        : "TX is not running"
                )
                .controlWidgetActionHint(
                    value.isActive
                        ? (isMuted ? "Unmute TX" : "Mute TX")
                        : "Start TX in MisMeeter first"
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
    struct Provider: ControlValueProvider {
        var previewValue: MisMeeterControlValue {
            MisMeeterControlValue(isActive: false, isMuted: false)
        }

        func currentValue() async throws -> MisMeeterControlValue {
            let snapshot = SharedAppState.readSnapshot()
            return MisMeeterControlValue(
                isActive: snapshot.isReceiving,
                isMuted: snapshot.isReceiveMuted
            )
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedControlStateStore.Kinds.receive,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "MisMeeter RX",
                isOn: value.isMuted,
                action: SetReceiveMuteControlIntent()
            ) { isMuted in
                Label(
                    value.isActive ? (isMuted ? "RX MUTED" : "RX ACTIVE") : "RX IDLE",
                    systemImage: rxSymbol(
                        active: value.isActive,
                        muted: value.isActive && isMuted
                    )
                )
                .controlWidgetStatus(
                    value.isActive
                        ? (isMuted ? "RX audio muted" : "RX audio active")
                        : "RX is not running"
                )
                .controlWidgetActionHint(
                    value.isActive
                        ? (isMuted ? "Unmute RX" : "Mute RX")
                        : "Start RX in MisMeeter first"
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

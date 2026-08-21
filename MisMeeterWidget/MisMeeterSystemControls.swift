import AppIntents
import SwiftUI
import WidgetKit

/// The value rendered by a system Control.
///
/// `isOn` alone is not sufficient for MisMeeter because a mute toggle must also
/// know whether the corresponding transport is actually running. Keeping both bits
/// in the provider value lets WidgetKit render and disable the control from one
/// coherent App Group snapshot.
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
/// Apple expects a stateful ControlWidgetToggle to expose its current value through
/// a `ControlValueProvider`. WidgetKit asks `currentValue()` whenever the control is
/// rendered and again after its SetValueIntent finishes. The provider reads the same
/// atomic App Group snapshot used by the app, widgets and Live Activity, so there is
/// still a single source of truth and no Control-specific cache.
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
            // A stale system surface must never be able to issue a meaningful mute
            // command when the transport is not running. Runtime guards remain as a
            // second line of defense for an interaction already in flight.
            .disabled(!value.isActive)
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
            .disabled(!value.isActive)
        }
        .displayName("MisMeeter RX Mute")
        .description("Mute or unmute MisMeeter receive playback.")
    }

    private func rxSymbol(active: Bool, muted: Bool) -> String {
        guard active else { return "speaker" }
        return muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }
}

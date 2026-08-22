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
            guard let snapshot = SharedAppState.readSnapshotIfAvailable() else {
                throw ControlStateUnavailable()
            }
            return snapshot.isMuted
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedControlStateStore.Kinds.microphone,
            provider: Provider()
        ) { isMuted in
            ControlWidgetToggle(
                "MisMeeter TX",
                isOn: isMuted,
                action: SetMicrophoneMuteControlIntent()
            ) { muted in
                Label(
                    muted ? "TX MUTED" : "TX ACTIVE",
                    systemImage: muted ? "mic.slash.fill" : "mic.fill"
                )
                .controlWidgetStatus(muted ? "TX microphone muted" : "TX microphone active")
                .controlWidgetActionHint(muted ? "Unmute TX" : "Mute TX")
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
            guard let snapshot = SharedAppState.readSnapshotIfAvailable() else {
                throw ControlStateUnavailable()
            }
            return snapshot.isReceiveMuted
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedControlStateStore.Kinds.receive,
            provider: Provider()
        ) { isMuted in
            ControlWidgetToggle(
                "MisMeeter RX",
                isOn: isMuted,
                action: SetReceiveMuteControlIntent()
            ) { muted in
                Label(
                    muted ? "RX MUTED" : "RX ACTIVE",
                    systemImage: muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
                )
                .controlWidgetStatus(muted ? "RX audio muted" : "RX audio active")
                .controlWidgetActionHint(muted ? "Unmute RX" : "Mute RX")
            }
            .tint(.red)
        }
        .displayName("MisMeeter RX Mute")
        .description("Mute or unmute MisMeeter receive playback.")
    }
}

private struct ControlStateUnavailable: LocalizedError {
    var errorDescription: String? { "MisMeeter control state is temporarily unavailable" }
}

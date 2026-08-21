import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Small value object rendered by Control Center / Lock Screen.
/// `isMuted` is the toggle value: ON means mute is engaged, matching the
/// native Silent Mode mental model and allowing iOS to highlight mute in red.
struct TransportControlValue: Sendable {
    let isAvailable: Bool
    let isMuted: Bool
}

private enum MisMeeterControlStateResolver {
    /// Prefer ActivityKit while a MisMeeter Live Activity exists. It is already the
    /// state source rendered in the Dynamic Island, so the Controls and Island stay
    /// visually consistent. Fall back to the newest App Group snapshot otherwise.
    static func snapshot() -> SharedTransportSnapshot {
        if let activity = Activity<MicActivityAttributes>.activities.first(where: {
            $0.activityState == .active || $0.activityState == .stale
        }) {
            let state = activity.content.state
            if state.isStreaming || state.isReceiving {
                let shared = SharedAppState.readSnapshot()
                return SharedTransportSnapshot(
                    isStreaming: state.isStreaming,
                    isMuted: state.isMuted,
                    isReceiving: state.isReceiving,
                    isReceiveMuted: state.isReceiveMuted,
                    presetName: state.presetLabel,
                    sendPresetName: state.sendPresetLabel,
                    receivePresetName: state.receivePresetLabel,
                    destination: state.destinationLabel,
                    streamName: shared.streamName,
                    startedAt: state.startedAt,
                    status: state.statusLabel,
                    publishedAt: shared.publishedAt
                )
            }
        }
        return SharedAppState.readSnapshot()
    }
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedAppState.ControlKinds.microphone,
            provider: Provider()
        ) { state in
            ControlWidgetToggle(
                "MisMeeter TX",
                isOn: state.isAvailable && state.isMuted,
                action: SetMicrophoneMuteControlIntent()
            ) { isMuted in
                Label(
                    state.isAvailable ? (isMuted ? "TX MUTED" : "TX ACTIVE") : "TX IDLE",
                    systemImage: state.isAvailable
                        ? (isMuted ? "mic.slash.fill" : "mic.fill")
                        : "mic"
                )
            }
            // ON == muted. iOS therefore renders mute as an illuminated red toggle,
            // the same native interaction model used by Silent Mode.
            .tint(.red)
        }
        .displayName("MisMeeter TX Mute")
        .description("Mute or unmute the active MisMeeter microphone transmission.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: TransportControlValue {
            TransportControlValue(isAvailable: true, isMuted: false)
        }

        func currentValue() async throws -> TransportControlValue {
            let snapshot = MisMeeterControlStateResolver.snapshot()
            return TransportControlValue(
                isAvailable: snapshot.isStreaming,
                isMuted: snapshot.isMuted
            )
        }
    }
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterReceiveMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedAppState.ControlKinds.receive,
            provider: Provider()
        ) { state in
            ControlWidgetToggle(
                "MisMeeter RX",
                isOn: state.isAvailable && state.isMuted,
                action: SetReceiveMuteControlIntent()
            ) { isMuted in
                Label(
                    state.isAvailable ? (isMuted ? "RX MUTED" : "RX ACTIVE") : "RX IDLE",
                    systemImage: state.isAvailable
                        ? (isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                        : "speaker"
                )
            }
            .tint(.red)
        }
        .displayName("MisMeeter RX Mute")
        .description("Mute or unmute active MisMeeter receive playback.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: TransportControlValue {
            TransportControlValue(isAvailable: true, isMuted: false)
        }

        func currentValue() async throws -> TransportControlValue {
            let snapshot = MisMeeterControlStateResolver.snapshot()
            return TransportControlValue(
                isAvailable: snapshot.isReceiving,
                isMuted: snapshot.isReceiveMuted
            )
        }
    }
}

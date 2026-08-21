import AppIntents
import SwiftUI
import WidgetKit

/// Snapshot-backed state used by the native iOS Controls.
/// `isOn` means the audio path is currently audible/active, while
/// `isAvailable` means the corresponding transport actually exists.
struct TransportControlValue: Sendable {
    let isOn: Bool
    let isAvailable: Bool
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedAppState.ControlKinds.microphone,
            provider: Provider()
        ) { state in
            ControlWidgetToggle(
                "TX",
                isOn: state.isOn,
                action: SetMicrophoneEnabledIntent()
            ) { isOn in
                Label {
                    Text(state.isAvailable ? (isOn ? "TX ON" : "TX MUTED") : "TX IDLE")
                } icon: {
                    Image(systemName: state.isAvailable
                        ? (isOn ? "mic.fill" : "mic.slash.fill")
                        : "mic")
                }
                .controlWidgetStatus(
                    state.isAvailable
                        ? (isOn ? "TX microphone active" : "TX microphone muted")
                        : "TX is not running"
                )
                .controlWidgetActionHint(
                    state.isAvailable
                        ? (isOn ? "Mute TX microphone" : "Unmute TX microphone")
                        : "TX is idle"
                )
            }
            // Use one stable tint. Control Center uses the tint to make the ON
            // state visibly active; OFF remains neutral, while the slash symbol
            // and explicit status distinguish mute from active at every size.
            .tint(.green)
            .disabled(!state.isAvailable)
        }
        .displayName("MisMeeter TX")
        .description("Mute or unmute the active MisMeeter microphone transmission.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: TransportControlValue {
            TransportControlValue(isOn: true, isAvailable: true)
        }

        func currentValue() async throws -> TransportControlValue {
            let snapshot = SharedAppState.readSnapshot()
            return TransportControlValue(
                isOn: snapshot.isStreaming && !snapshot.isMuted,
                isAvailable: snapshot.isStreaming
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
                "RX",
                isOn: state.isOn,
                action: SetReceiveEnabledIntent()
            ) { isOn in
                Label {
                    Text(state.isAvailable ? (isOn ? "RX ON" : "RX MUTED") : "RX IDLE")
                } icon: {
                    Image(systemName: state.isAvailable
                        ? (isOn ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        : "speaker")
                }
                .controlWidgetStatus(
                    state.isAvailable
                        ? (isOn ? "RX audio active" : "RX audio muted")
                        : "RX is not running"
                )
                .controlWidgetActionHint(
                    state.isAvailable
                        ? (isOn ? "Mute RX audio" : "Unmute RX audio")
                        : "RX is idle"
                )
            }
            .tint(.green)
            .disabled(!state.isAvailable)
        }
        .displayName("MisMeeter RX")
        .description("Mute or unmute active MisMeeter receive playback.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: TransportControlValue {
            TransportControlValue(isOn: true, isAvailable: true)
        }

        func currentValue() async throws -> TransportControlValue {
            let snapshot = SharedAppState.readSnapshot()
            return TransportControlValue(
                isOn: snapshot.isReceiving && !snapshot.isReceiveMuted,
                isAvailable: snapshot.isReceiving
            )
        }
    }
}

import AppIntents
import SwiftUI
import WidgetKit

/// Snapshot-backed state used by the native iOS Controls.
/// `isOn` is the value rendered by the toggle, while `isAvailable` prevents
/// controls from pretending they can change an inactive transport.
struct TransportControlValue {
    let isOn: Bool
    let isAvailable: Bool
}

/// Native iOS 18 Controls are MisMeeter's primary locked-device interaction surface.
/// They use ControlWidgetToggle + SetValueIntent, so iOS sends an explicit target value
/// instead of forcing the app to infer a blind toggle from potentially stale UI state.
@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedAppState.ControlKinds.microphone,
            provider: Provider()
        ) { state in
            ControlWidgetToggle(
                "MisMeeter Mic",
                isOn: state.isOn,
                action: SetMicrophoneEnabledIntent()
            ) { isOn in
                Label(
                    state.isAvailable ? (isOn ? "Mic On" : "Mic Muted") : "Mic Idle",
                    systemImage: state.isAvailable
                        ? (isOn ? "mic.fill" : "mic.slash.fill")
                        : "mic"
                )
            }
            .disabled(!state.isAvailable)
            .tint(state.isAvailable ? (state.isOn ? .green : .red) : .gray)
        }
        .displayName("MisMeeter Microphone")
        .description("Enable or mute the active MisMeeter microphone transmission.")
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
                "MisMeeter RX",
                isOn: state.isOn,
                action: SetReceiveEnabledIntent()
            ) { isOn in
                Label(
                    state.isAvailable ? (isOn ? "RX On" : "RX Muted") : "RX Idle",
                    systemImage: state.isAvailable
                        ? (isOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        : "speaker"
                )
            }
            .disabled(!state.isAvailable)
            .tint(state.isAvailable ? (state.isOn ? .green : .red) : .gray)
        }
        .displayName("MisMeeter Receive")
        .description("Enable or mute the active MisMeeter receive audio.")
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

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterStopAllControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedAppState.ControlKinds.stopAll,
            provider: Provider()
        ) { isActive in
            ControlWidgetButton(action: EndLiveActivityIntent()) {
                Label(
                    isActive ? "Stop All" : "MisMeeter Idle",
                    systemImage: isActive ? "stop.fill" : "stop.circle"
                )
            }
            .disabled(!isActive)
            .tint(.red)
        }
        .displayName("Stop MisMeeter")
        .description("Stop all active MisMeeter transmission and reception.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { true }

        func currentValue() async throws -> Bool {
            let snapshot = SharedAppState.readSnapshot()
            return snapshot.isStreaming || snapshot.isReceiving
        }
    }
}

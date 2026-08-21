import AppIntents
import SwiftUI
import WidgetKit

/// Runtime-backed state used by MisMeeter's native iOS Controls.
///
/// These controls intentionally use `ControlWidgetButton` rather than
/// `ControlWidgetToggle`. A system toggle visually de-emphasizes its OFF state,
/// which is the wrong semantic for MisMeeter: "muted" is still an important,
/// active transport state. A button lets us keep the control illuminated and
/// communicate the real state explicitly with tint + SF Symbol:
///
/// - green + normal symbol  -> path is active / audible
/// - red + slashed symbol   -> path is active but muted
/// - neutral + plain symbol -> transport is idle; tapping safely performs no action
struct TransportControlValue: Sendable {
    let isAvailable: Bool
    let isMuted: Bool
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedAppState.ControlKinds.microphone,
            provider: Provider()
        ) { state in
            ControlWidgetButton(action: ToggleMicrophoneControlIntent()) {
                Label {
                    Text(Self.title(for: state))
                } icon: {
                    Image(systemName: Self.symbol(for: state))
                        .contentTransition(.identity)
                }
                .controlWidgetStatus(Self.status(for: state))
                .controlWidgetActionHint(Self.actionHint(for: state))
            }
            // Keep mute visually prominent. Unlike ControlWidgetToggle, a button
            // doesn't turn the muted state into a neutral "OFF" appearance. The
            // button deliberately remains tappable even if WidgetKit briefly renders
            // an IDLE value; the AppIntent re-checks the authoritative shared state.
            .tint(Self.tint(for: state))
        }
        .displayName("MisMeeter TX")
        .description("Mute or unmute the active MisMeeter microphone transmission.")
    }

    private static func title(for state: TransportControlValue) -> String {
        guard state.isAvailable else { return "TX IDLE" }
        return state.isMuted ? "TX MUTED" : "TX ON"
    }

    private static func symbol(for state: TransportControlValue) -> String {
        guard state.isAvailable else { return "mic" }
        return state.isMuted ? "mic.slash.fill" : "mic.fill"
    }

    private static func tint(for state: TransportControlValue) -> Color? {
        guard state.isAvailable else { return nil }
        return state.isMuted ? .red : .green
    }

    private static func status(for state: TransportControlValue) -> String {
        guard state.isAvailable else { return "TX is not running" }
        return state.isMuted ? "TX microphone muted" : "TX microphone active"
    }

    private static func actionHint(for state: TransportControlValue) -> String {
        guard state.isAvailable else { return "TX is idle" }
        return state.isMuted ? "Unmute TX microphone" : "Mute TX microphone"
    }

    struct Provider: ControlValueProvider {
        var previewValue: TransportControlValue {
            TransportControlValue(isAvailable: true, isMuted: false)
        }

        func currentValue() async throws -> TransportControlValue {
            let snapshot = SharedAppState.readSnapshot()
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
            ControlWidgetButton(action: ToggleReceiveControlIntent()) {
                Label {
                    Text(Self.title(for: state))
                } icon: {
                    Image(systemName: Self.symbol(for: state))
                        .contentTransition(.identity)
                }
                .controlWidgetStatus(Self.status(for: state))
                .controlWidgetActionHint(Self.actionHint(for: state))
            }
            // Do not disable from provider state. A cached IDLE render must never
            // make the control permanently untappable; the intent performs its own
            // runtime availability check.
            .tint(Self.tint(for: state))
        }
        .displayName("MisMeeter RX")
        .description("Mute or unmute active MisMeeter receive playback.")
    }

    private static func title(for state: TransportControlValue) -> String {
        guard state.isAvailable else { return "RX IDLE" }
        return state.isMuted ? "RX MUTED" : "RX ON"
    }

    private static func symbol(for state: TransportControlValue) -> String {
        guard state.isAvailable else { return "speaker" }
        return state.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }

    private static func tint(for state: TransportControlValue) -> Color? {
        guard state.isAvailable else { return nil }
        return state.isMuted ? .red : .green
    }

    private static func status(for state: TransportControlValue) -> String {
        guard state.isAvailable else { return "RX is not running" }
        return state.isMuted ? "RX audio muted" : "RX audio active"
    }

    private static func actionHint(for state: TransportControlValue) -> String {
        guard state.isAvailable else { return "RX is idle" }
        return state.isMuted ? "Unmute RX audio" : "Mute RX audio"
    }

    struct Provider: ControlValueProvider {
        var previewValue: TransportControlValue {
            TransportControlValue(isAvailable: true, isMuted: false)
        }

        func currentValue() async throws -> TransportControlValue {
            let snapshot = SharedAppState.readSnapshot()
            return TransportControlValue(
                isAvailable: snapshot.isReceiving,
                isMuted: snapshot.isReceiveMuted
            )
        }
    }
}

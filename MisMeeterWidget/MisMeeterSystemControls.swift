import AppIntents
import SwiftUI
import WidgetKit

/// Presentation value used by Control Center. `isMuted` is the actual toggle value;
/// `isActive` only selects the state label/symbol so ACTIVE and IDLE are visually
/// distinguishable without changing SetValueIntent semantics.
struct MuteControlPresentationValue: Sendable {
    let isActive: Bool
    let isMuted: Bool
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedControlStateStore.Kinds.microphone,
            provider: Provider()
        ) { state in
            ControlWidgetToggle(
                "MisMeeter TX",
                isOn: state.isMuted,
                action: SetMicrophoneMuteControlIntent()
            ) { requestedValue in
                let muted = state.isActive && requestedValue
                Label(
                    state.isActive ? (muted ? "TX MUTED" : "TX ACTIVE") : "TX IDLE",
                    systemImage: txSymbol(active: state.isActive, muted: muted)
                )
                .controlWidgetStatus(
                    state.isActive
                        ? (muted ? "TX microphone muted" : "TX microphone active")
                        : "TX is not running"
                )
                .controlWidgetActionHint(
                    state.isActive
                        ? (muted ? "Unmute TX" : "Mute TX")
                        : "No active TX session"
                )
            }
            // ON == muted, matching the system visual language used by mute/silent
            // controls. ACTIVE-unmuted is distinguished from IDLE by its filled icon.
            .tint(.red)
        }
        .displayName("MisMeeter TX Mute")
        .description("Mute or unmute MisMeeter microphone transmission.")
    }

    struct Provider: ControlValueProvider {
        let previewValue = MuteControlPresentationValue(isActive: true, isMuted: false)

        func currentValue() async throws -> MuteControlPresentationValue {
            let state = SharedControlStateStore.read()
            return MuteControlPresentationValue(
                isActive: state.txActive,
                isMuted: state.txActive && state.txMuted
            )
        }
    }

    private func txSymbol(active: Bool, muted: Bool) -> String {
        guard active else { return "mic" }
        return muted ? "mic.slash.fill" : "mic.fill"
    }
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterReceiveMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedControlStateStore.Kinds.receive,
            provider: Provider()
        ) { state in
            ControlWidgetToggle(
                "MisMeeter RX",
                isOn: state.isMuted,
                action: SetReceiveMuteControlIntent()
            ) { requestedValue in
                let muted = state.isActive && requestedValue
                Label(
                    state.isActive ? (muted ? "RX MUTED" : "RX ACTIVE") : "RX IDLE",
                    systemImage: rxSymbol(active: state.isActive, muted: muted)
                )
                .controlWidgetStatus(
                    state.isActive
                        ? (muted ? "RX audio muted" : "RX audio active")
                        : "RX is not running"
                )
                .controlWidgetActionHint(
                    state.isActive
                        ? (muted ? "Unmute RX" : "Mute RX")
                        : "No active RX session"
                )
            }
            .tint(.red)
        }
        .displayName("MisMeeter RX Mute")
        .description("Mute or unmute MisMeeter receive playback.")
    }

    struct Provider: ControlValueProvider {
        let previewValue = MuteControlPresentationValue(isActive: true, isMuted: false)

        func currentValue() async throws -> MuteControlPresentationValue {
            let state = SharedControlStateStore.read()
            return MuteControlPresentationValue(
                isActive: state.rxActive,
                isMuted: state.rxActive && state.rxMuted
            )
        }
    }

    private func rxSymbol(active: Bool, muted: Bool) -> String {
        guard active else { return "speaker" }
        return muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }
}

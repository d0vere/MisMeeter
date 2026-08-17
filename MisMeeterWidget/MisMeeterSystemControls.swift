import AppIntents
import SwiftUI
import WidgetKit

/// iOS 18 system Controls are the supported surface for immediate actions from
/// Control Center, the Lock Screen controls area, and the Action button.
///
/// Unlike traditional Lock Screen widgets, Controls are designed specifically
/// for actions. The intents explicitly opt into `.alwaysAllowed` so the action
/// itself doesn't request authentication when iOS permits locked-device use.
@available(iOSApplicationExtension 18.0, *)
struct MisMeeterReceiveMuteControl: ControlWidget {
    static let kind = "dev.mismeeter.app.control.receiveMute"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleReceiveMuteIntent()) {
                Label("Toggle Receive", systemImage: "speaker.wave.2.fill")
            }
        }
        .displayName("MisMeeter Receive")
        .description("Mute or unmute MisMeeter receive audio.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterMicrophoneMuteControl: ControlWidget {
    static let kind = "dev.mismeeter.app.control.microphoneMute"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleMuteIntent()) {
                Label("Toggle Microphone", systemImage: "mic.fill")
            }
        }
        .displayName("MisMeeter Microphone")
        .description("Mute or unmute the active MisMeeter microphone transmission.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct MisMeeterStopAllControl: ControlWidget {
    static let kind = "dev.mismeeter.app.control.stopAll"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: EndLiveActivityIntent()) {
                Label("Stop MisMeeter", systemImage: "stop.fill")
            }
        }
        .displayName("Stop MisMeeter")
        .description("Stop MisMeeter transmission and reception.")
    }
}

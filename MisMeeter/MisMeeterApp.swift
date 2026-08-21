import SwiftUI
import WidgetKit

@main
struct MisMeeterApp: App {
    init() {
        // 3.3.6 changes the Control Center template from a system toggle to a
        // state-aware button while intentionally preserving the same control kinds.
        // Force configured controls to rebuild their templates after an app update
        // instead of waiting for the next transport-state transition.
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

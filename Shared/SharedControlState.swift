import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Shared identifiers and invalidation helpers for MisMeeter's iOS 18 system Controls.
///
/// Controls do not keep a second copy of transport state. Their ControlValueProvider
/// reads `SharedAppState`, the same atomic App Group snapshot used by the app/widget/
/// Live Activity. This preserves a single source of truth while using WidgetKit's
/// documented state-provider lifecycle.
enum SharedControlStateStore {
    enum Kinds {
        // Keep v4 kinds stable so existing Control Center / Lock Screen placements
        // survive the 4.0.x updates.
        static let receive = "dev.mismeeter.app.control.v4.receiveMute"
        static let microphone = "dev.mismeeter.app.control.v4.microphoneMute"
    }

    #if canImport(WidgetKit)
    /// Apple documents `reloadControls(ofKind:)` as the app-side invalidation path
    /// when state changes outside the Control itself. Use the exact configured kinds
    /// rather than a broad reload so SpringBoard invalidates these two templates.
    static func reloadMisMeeterControls() {
        guard #available(iOS 18.0, *) else { return }
        ControlCenter.shared.reloadControls(ofKind: Kinds.receive)
        ControlCenter.shared.reloadControls(ofKind: Kinds.microphone)
    }
    #endif
}

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Shared identifiers and invalidation helpers for MisMeeter's iOS 18 system Controls.
///
/// The Controls deliberately do NOT keep a second copy of transport state. Their
/// visual value is derived directly from `SharedAppState`, the same atomic App Group
/// snapshot used by the app/widget/Live Activity. This removes the split-state cache
/// that existed in 4.0.1.
enum SharedControlStateStore {
    enum Kinds {
        // Keep v4 kinds stable so existing Control Center / Lock Screen placements
        // survive the 4.0.1 -> 4.0.2 update.
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

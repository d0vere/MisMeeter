import SwiftUI
import UIKit

/// Bridges the small amount of process lifecycle state that system Controls need.
/// Audio/background lifecycle remains owned by MisMeeterRuntime.
final class MisMeeterAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // A new process cannot own a previous process's VBAN session. Publish the
        // freshly-created runtime state and invalidate any cached highlighted control
        // left by a prior termination before the main UI even appears.
        MisMeeterRuntime.shared.refreshSystemControls()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Reassert the latest authoritative state when the UI leaves the foreground.
        // This does not stop background audio; it only refreshes the system Controls.
        MisMeeterRuntime.shared.refreshSystemControls()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Best effort. iOS doesn't guarantee this callback for every force-quit of a
        // background-capable app, but when delivered it prevents a stale highlighted
        // mute state from surviving normal process termination.
        MisMeeterRuntime.shared.prepareForProcessTermination()
    }
}

@main
struct MisMeeterApp: App {
    @UIApplicationDelegateAdaptor(MisMeeterAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

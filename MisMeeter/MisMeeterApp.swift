import SwiftUI
import UIKit

/// Bridges the small amount of process lifecycle state that system Controls need.
/// Audio/background lifecycle remains owned by MisMeeterRuntime.
final class MisMeeterAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // A LiveActivityIntent can launch this process in the background. Do not
        // publish the newly-created runtime's default idle state here: that would
        // overwrite the App Group snapshot before the Control intent completes.
        MisMeeterRuntime.shared.invalidateSystemControlsOnly()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // A Control's LiveActivityIntent may cold-launch the app directly into the
        // background. Never publish runtime defaults from this lifecycle callback:
        // doing so can overwrite the App Group value that ControlValueProvider uses.
        // Runtime commands themselves publish authoritative state.
        MisMeeterRuntime.shared.invalidateSystemControlsOnly()
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

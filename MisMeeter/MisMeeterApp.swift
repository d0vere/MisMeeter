import SwiftUI
import UIKit

final class MisMeeterAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MisMeeterRuntime.shared.invalidateSystemControlsOnly()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        MisMeeterRuntime.shared.invalidateSystemControlsOnly()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        MisMeeterRuntime.shared.prepareForProcessTermination()
    }
}

@main
struct MisMeeterApp: App {
    @UIApplicationDelegateAdaptor(MisMeeterAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
    }
}

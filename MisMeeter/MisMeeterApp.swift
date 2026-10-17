import SwiftUI
import UIKit

/// Adds a real safe-area inset matching the keyboard overlap. DashboardView intentionally
/// ignores the system keyboard safe area so the floating navigation does not jump; this
/// controller restores only the usable content inset, allowing Form to scroll the focused
/// preset field into view while typing.
@MainActor
final class KeyboardAvoidanceController {
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.update(from: note) }
        })
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.hide(from: note) }
        })
    }

    private func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private func update(from notification: Notification) {
        guard let window = activeWindow(),
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        // Clear the previous custom inset before measuring the new overlap.
        window.rootViewController?.additionalSafeAreaInsets.bottom = 0
        let keyboardFrame = window.convert(frame, from: nil)
        let overlap = max(0, window.bounds.maxY - keyboardFrame.minY - window.safeAreaInsets.bottom)
        apply(bottom: overlap, notification: notification, window: window)
    }

    private func hide(from notification: Notification) {
        guard let window = activeWindow() else { return }
        apply(bottom: 0, notification: notification, window: window)
    }

    private func apply(bottom: CGFloat, notification: Notification, window: UIWindow) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let rawCurve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        let options = UIView.AnimationOptions(rawValue: rawCurve << 16)
        UIView.animate(withDuration: duration, delay: 0, options: [options, .beginFromCurrentState]) {
            window.rootViewController?.additionalSafeAreaInsets.bottom = bottom
            window.layoutIfNeeded()
        }
    }
}

final class MisMeeterAppDelegate: NSObject, UIApplicationDelegate {
    private let keyboardAvoidance = KeyboardAvoidanceController()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MisMeeterRuntime.shared.invalidateSystemControlsOnly()
        keyboardAvoidance.start()
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

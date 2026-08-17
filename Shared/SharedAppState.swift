import CoreFoundation
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct SharedTransportSnapshot: Codable, Hashable {
    var isStreaming = false
    var isMuted = false
    var isReceiving = false
    var presetName = "MisMeeter"
    var destination = "Not connected"
    var streamName = "MisMeeter"
    var startedAt: Date?
    var status = "Ready"

    static let idle = SharedTransportSnapshot()
}

enum SharedControlAction: Int, Codable {
    case toggleMute = 1
    case stopStreaming = 2
}

enum SharedAppState {
    static let appGroup = "group.dev.mismeeter.app"
    static let controlNotification = "dev.mismeeter.app.control"
    private static let snapshotKey = "transport.snapshot.v3"
    private static let actionKey = "control.action.v3"
    private static let actionIDKey = "control.action.id.v3"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func readSnapshot() -> SharedTransportSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let value = try? JSONDecoder().decode(SharedTransportSnapshot.self, from: data)
        else { return .idle }
        return value
    }

    static func writeSnapshot(_ value: SharedTransportSnapshot, reloadWidgets: Bool = true) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: snapshotKey)
        }
        if reloadWidgets {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    static func issue(_ action: SharedControlAction) {
        defaults.set(action.rawValue, forKey: actionKey)
        defaults.set(UUID().uuidString, forKey: actionIDKey)
        defaults.synchronize()
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(controlNotification as CFString),
            nil,
            nil,
            true
        )
    }

    static func pendingAction() -> (id: String, action: SharedControlAction)? {
        guard let id = defaults.string(forKey: actionIDKey),
              let action = SharedControlAction(rawValue: defaults.integer(forKey: actionKey))
        else { return nil }
        return (id, action)
    }
}

final class SharedControlObserver {
    private var lastActionID: String?
    private var handler: ((SharedControlAction) -> Void)?

    func start(handler: @escaping (SharedControlAction) -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let object = Unmanaged<SharedControlObserver>.fromOpaque(observer).takeUnretainedValue()
                object.consumePendingAction()
            },
            SharedAppState.controlNotification as CFString,
            nil,
            .deliverImmediately
        )
        consumePendingAction()
    }

    func stop() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )
    }

    private func consumePendingAction() {
        guard let pending = SharedAppState.pendingAction(), pending.id != lastActionID else { return }
        lastActionID = pending.id
        handler?(pending.action)
    }

    deinit { stop() }
}

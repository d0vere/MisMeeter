import CoreFoundation
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct SharedTransportSnapshot: Codable, Hashable {
    var isStreaming = false
    var isMuted = false
    var isReceiving = false
    var isReceiveMuted = false
    var presetName = "MisMeeter"
    var sendPresetName = "MisMeeter"
    var receivePresetName = "MisMeeter"
    var destination = "Not connected"
    var streamName = "MisMeeter"
    var startedAt: Date?
    var status = "Ready"

    static let idle = SharedTransportSnapshot()

    private enum CodingKeys: String, CodingKey {
        case isStreaming, isMuted, isReceiving, isReceiveMuted
        case presetName, sendPresetName, receivePresetName
        case destination, streamName, startedAt, status
    }

    init(
        isStreaming: Bool = false,
        isMuted: Bool = false,
        isReceiving: Bool = false,
        isReceiveMuted: Bool = false,
        presetName: String = "MisMeeter",
        sendPresetName: String? = nil,
        receivePresetName: String? = nil,
        destination: String = "Not connected",
        streamName: String = "MisMeeter",
        startedAt: Date? = nil,
        status: String = "Ready"
    ) {
        self.isStreaming = isStreaming
        self.isMuted = isMuted
        self.isReceiving = isReceiving
        self.isReceiveMuted = isReceiveMuted
        self.presetName = presetName
        self.sendPresetName = sendPresetName ?? presetName
        self.receivePresetName = receivePresetName ?? presetName
        self.destination = destination
        self.streamName = streamName
        self.startedAt = startedAt
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isReceiving = try container.decodeIfPresent(Bool.self, forKey: .isReceiving) ?? false
        isReceiveMuted = try container.decodeIfPresent(Bool.self, forKey: .isReceiveMuted) ?? false
        presetName = try container.decodeIfPresent(String.self, forKey: .presetName) ?? "MisMeeter"
        sendPresetName = try container.decodeIfPresent(String.self, forKey: .sendPresetName) ?? presetName
        receivePresetName = try container.decodeIfPresent(String.self, forKey: .receivePresetName) ?? presetName
        destination = try container.decodeIfPresent(String.self, forKey: .destination) ?? "Not connected"
        streamName = try container.decodeIfPresent(String.self, forKey: .streamName) ?? "MisMeeter"
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "Ready"
    }
}

enum SharedControlAction: Int, Codable {
    case toggleMicrophoneMute = 1
    case stopAll = 2
    case toggleReceiveMute = 3
}

enum SharedAppState {
    static let appGroup = "group.dev.mismeeter.app"
    static let controlNotification = "dev.mismeeter.app.control"
    private static let snapshotKey = "transport.snapshot.v4"
    private static let actionKey = "control.action.v4"
    private static let actionIDKey = "control.action.id.v4"

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

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
    /// The command carries the exact desired mute value. This is intentionally
    /// not a blind toggle: Control Center can render from stale state and a
    /// toggle-at-receipt would invert the wrong value.
    case setMicrophoneMuted = 1
    case stopAll = 2
    case setReceiveMuted = 3
}

struct SharedControlCommand: Codable, Hashable {
    let id: String
    let action: SharedControlAction
    let value: Bool?

    init(action: SharedControlAction, value: Bool? = nil) {
        self.id = UUID().uuidString
        self.action = action
        self.value = value
    }
}

enum SharedAppState {
    static let appGroup = "group.dev.mismeeter.app"
    static let controlNotification = "dev.mismeeter.app.control.v5"

    enum ControlKinds {
        static let receive = "dev.mismeeter.app.control.receiveMute"
        static let microphone = "dev.mismeeter.app.control.microphoneMute"
        static let stopAll = "dev.mismeeter.app.control.stopAll"
    }

    private static let snapshotKey = "transport.snapshot.v4"
    private static let commandKey = "control.command.v5"

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
        let previous = readSnapshot()

        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: snapshotKey)
        }

        guard reloadWidgets else { return }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()

        if #available(iOS 18.0, *) {
            // Controls don't automatically refresh when state is changed from
            // the app or Live Activity. Reload only the controls whose rendered
            // value can have changed.
            if previous.isStreaming != value.isStreaming || previous.isMuted != value.isMuted {
                ControlCenter.shared.reloadControls(ofKind: ControlKinds.microphone)
            }
            if previous.isReceiving != value.isReceiving || previous.isReceiveMuted != value.isReceiveMuted {
                ControlCenter.shared.reloadControls(ofKind: ControlKinds.receive)
            }
            if previous.isStreaming != value.isStreaming || previous.isReceiving != value.isReceiving {
                ControlCenter.shared.reloadControls(ofKind: ControlKinds.stopAll)
            }
        }
        #endif
    }

    static func issue(_ action: SharedControlAction, value: Bool? = nil) {
        let command = SharedControlCommand(action: action, value: value)
        if let data = try? JSONEncoder().encode(command) {
            defaults.set(data, forKey: commandKey)
        }
        defaults.synchronize()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(controlNotification as CFString),
            nil,
            nil,
            true
        )
    }

    static func pendingCommand() -> SharedControlCommand? {
        guard let data = defaults.data(forKey: commandKey) else { return nil }
        return try? JSONDecoder().decode(SharedControlCommand.self, from: data)
    }

    /// Polls the runtime-owned shared snapshot for a short acknowledgement window.
    /// Controls use this after issuing an exact command so their rendered state is
    /// derived from what the audio engine actually applied, not from optimistic UI.
    @discardableResult
    static func waitForSnapshot(
        timeoutMilliseconds: Int,
        pollMilliseconds: Int = 50,
        until predicate: (SharedTransportSnapshot) -> Bool
    ) async -> Bool {
        let safeTimeout = max(0, timeoutMilliseconds)
        let safePoll = max(20, pollMilliseconds)
        let deadline = Date().addingTimeInterval(Double(safeTimeout) / 1_000.0)

        repeat {
            if predicate(readSnapshot()) { return true }
            if Date() >= deadline { break }
            try? await Task.sleep(nanoseconds: UInt64(safePoll) * 1_000_000)
        } while !Task.isCancelled

        return predicate(readSnapshot())
    }
}

final class SharedControlObserver {
    private var lastCommandID: String?
    private var handler: ((SharedControlCommand) -> Void)?

    func start(handler: @escaping (SharedControlCommand) -> Void) {
        self.handler = handler

        // Never replay a command left over from a previous process lifetime.
        // Commands are for controlling an already-running audio runtime.
        lastCommandID = SharedAppState.pendingCommand()?.id

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let object = Unmanaged<SharedControlObserver>.fromOpaque(observer).takeUnretainedValue()
                object.consumePendingCommand()
            },
            SharedAppState.controlNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    func stop() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )
    }

    private func consumePendingCommand() {
        guard let pending = SharedAppState.pendingCommand(), pending.id != lastCommandID else { return }
        lastCommandID = pending.id
        handler?(pending)
    }

    deinit { stop() }
}

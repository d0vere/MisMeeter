import CoreFoundation
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct SharedTransportSnapshot: Codable, Hashable, Sendable {
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

enum SharedControlAction: Int, Codable, CaseIterable, Hashable, Sendable {
    /// The command carries the exact desired mute value. This is intentionally
    /// not a blind toggle: Control Center can render from stale state and a
    /// toggle-at-receipt would invert the wrong value.
    case setMicrophoneMuted = 1
    case stopAll = 2
    case setReceiveMuted = 3

    fileprivate var mailboxKey: String {
        switch self {
        case .setMicrophoneMuted:
            return "control.command.v7.microphone"
        case .setReceiveMuted:
            return "control.command.v7.receive"
        case .stopAll:
            return "control.command.v7.stopAll"
        }
    }

    fileprivate var mailboxFilename: String {
        switch self {
        case .setMicrophoneMuted:
            return "control-command-v7-microphone.json"
        case .setReceiveMuted:
            return "control-command-v7-receive.json"
        case .stopAll:
            return "control-command-v7-stop-all.json"
        }
    }
}

struct SharedControlCommand: Codable, Hashable, Sendable {
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
    static let controlNotification = "dev.mismeeter.app.control.v7"

    enum ControlKinds {
        static let receive = "dev.mismeeter.app.control.receiveMute"
        static let microphone = "dev.mismeeter.app.control.microphoneMute"
    }

    private static let snapshotKey = "transport.snapshot.v7"
    private static let snapshotFilename = "transport-snapshot-v7.json"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static var groupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static var snapshotURL: URL? {
        groupContainerURL?.appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    private static func commandURL(for action: SharedControlAction) -> URL? {
        groupContainerURL?.appendingPathComponent(action.mailboxFilename, isDirectory: false)
    }

    private static func writeSharedData(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // Controls are explicitly designed to work while the phone is locked.
            // Keep App Group state readable after the user's first unlock following
            // a reboot, which matches the lifetime of a running audio session.
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            // UserDefaults below remains the compatibility fallback.
        }
    }

    /// Reads the cross-process transport state. The App Group file is authoritative
    /// because atomic file replacement is immediately visible to the WidgetKit
    /// extension, unlike a freshly-mutated UserDefaults cache in another process.
    /// UserDefaults remains as a migration/fallback path for unusual environments.
    static func readSnapshot() -> SharedTransportSnapshot {
        if let url = snapshotURL,
           let data = try? Data(contentsOf: url),
           let value = try? JSONDecoder().decode(SharedTransportSnapshot.self, from: data) {
            return value
        }

        defaults.synchronize()
        guard let data = defaults.data(forKey: snapshotKey),
              let value = try? JSONDecoder().decode(SharedTransportSnapshot.self, from: data)
        else { return .idle }
        return value
    }

    static func writeSnapshot(_ value: SharedTransportSnapshot, reloadWidgets: Bool = true) {
        let previous = readSnapshot()

        if let data = try? JSONEncoder().encode(value) {
            // Write the shared file *before* asking WidgetKit to reload. This closes
            // the race where Control Center fetched the old IDLE state and cached a
            // disabled control even though the runtime had already started.
            if let url = snapshotURL {
                writeSharedData(data, to: url)
            }
            defaults.set(data, forKey: snapshotKey)
            defaults.synchronize()
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
        }
        #endif
    }

    static func issue(_ action: SharedControlAction, value: Bool? = nil) {
        let command = SharedControlCommand(action: action, value: value)
        if let data = try? JSONEncoder().encode(command) {
            // One atomic mailbox file per action. The file is committed before the
            // Darwin notification is posted, so the main process can never observe
            // the wake-up before the command itself is visible.
            if let url = commandURL(for: action) {
                writeSharedData(data, to: url)
            }
            defaults.set(data, forKey: action.mailboxKey)
            defaults.synchronize()
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(controlNotification as CFString),
            nil,
            nil,
            true
        )
    }

    static func pendingCommand(for action: SharedControlAction) -> SharedControlCommand? {
        if let url = commandURL(for: action),
           let data = try? Data(contentsOf: url),
           let command = try? JSONDecoder().decode(SharedControlCommand.self, from: data),
           command.action == action {
            return command
        }

        defaults.synchronize()
        guard let data = defaults.data(forKey: action.mailboxKey),
              let command = try? JSONDecoder().decode(SharedControlCommand.self, from: data),
              command.action == action
        else { return nil }
        return command
    }

    static func pendingCommands() -> [SharedControlCommand] {
        // Stop All is intentionally evaluated first. If it is new, the observer
        // treats it as dominant and ignores simultaneous mute requests.
        let order: [SharedControlAction] = [.stopAll, .setMicrophoneMuted, .setReceiveMuted]
        return order.compactMap { pendingCommand(for: $0) }
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
    private let lock = NSLock()
    private var lastCommandIDs: [SharedControlAction: String] = [:]
    private var handler: ((SharedControlCommand) -> Void)?

    func start(handler: @escaping (SharedControlCommand) -> Void) {
        self.handler = handler

        // Never replay commands left over from a previous process lifetime.
        // Commands only control an already-running audio runtime.
        lock.lock()
        lastCommandIDs = Dictionary(
            uniqueKeysWithValues: SharedAppState.pendingCommands().map { ($0.action, $0.id) }
        )
        lock.unlock()

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let object = Unmanaged<SharedControlObserver>.fromOpaque(observer).takeUnretainedValue()
                object.consumePendingCommands()
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
        lock.lock()
        handler = nil
        lock.unlock()
    }

    private func consumePendingCommands() {
        let pending = SharedAppState.pendingCommands()
        var fresh: [SharedControlCommand] = []

        lock.lock()
        for command in pending where lastCommandIDs[command.action] != command.id {
            lastCommandIDs[command.action] = command.id
            fresh.append(command)
        }
        let currentHandler = handler
        lock.unlock()

        guard let currentHandler, !fresh.isEmpty else { return }

        // Stop All dominates a burst. The mute mailboxes are still marked consumed,
        // preventing a late callback from trying to mutate a transport that is gone.
        if let stop = fresh.first(where: { $0.action == .stopAll }) {
            currentHandler(stop)
            return
        }

        for action in [SharedControlAction.setMicrophoneMuted, .setReceiveMuted] {
            if let command = fresh.first(where: { $0.action == action }) {
                currentHandler(command)
            }
        }
    }

    deinit { stop() }
}

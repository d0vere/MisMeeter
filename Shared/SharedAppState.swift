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
    /// Wall-clock publication time used only to choose the freshest cross-process
    /// copy when the App Group file and UserDefaults cache momentarily disagree.
    var publishedAt: Date?

    static let idle = SharedTransportSnapshot()

    private enum CodingKeys: String, CodingKey {
        case isStreaming, isMuted, isReceiving, isReceiveMuted
        case presetName, sendPresetName, receivePresetName
        case destination, streamName, startedAt, status, publishedAt
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
        status: String = "Ready",
        publishedAt: Date? = nil
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
        self.publishedAt = publishedAt
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
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
    }
}

enum SharedAppState {
    static let appGroup = "group.dev.mismeeter.app"

    enum ControlKinds {
        // Keep the existing kinds so users don't need to remove/re-add their controls.
        static let receive = "dev.mismeeter.app.control.receiveMute"
        static let microphone = "dev.mismeeter.app.control.microphoneMute"
    }

    // v8 deliberately ignores any stale v7 file left by 3.3.7.
    private static let snapshotKey = "transport.snapshot.v8"
    private static let snapshotFilename = "transport-snapshot-v8.json"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    private static func decodeSnapshot(_ data: Data?) -> SharedTransportSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(SharedTransportSnapshot.self, from: data)
    }

    /// Reads both App Group transports and chooses the newest valid copy.
    ///
    /// 3.3.7 always preferred the file whenever it could be decoded. If an atomic
    /// file replacement failed once, an old IDLE file could permanently shadow a
    /// newer UserDefaults snapshot. That is exactly the split-brain state visible
    /// when the Live Activity says RX is running but Control Center says it isn't.
    static func readSnapshot() -> SharedTransportSnapshot {
        let fileValue: SharedTransportSnapshot? = {
            guard let url = snapshotURL else { return nil }
            return decodeSnapshot(try? Data(contentsOf: url))
        }()

        defaults?.synchronize()
        let defaultsValue = decodeSnapshot(defaults?.data(forKey: snapshotKey))

        switch (fileValue, defaultsValue) {
        case let (file?, cached?):
            let fileDate = file.publishedAt ?? .distantPast
            let cachedDate = cached.publishedAt ?? .distantPast
            return fileDate >= cachedDate ? file : cached
        case let (file?, nil):
            return file
        case let (nil, cached?):
            return cached
        case (nil, nil):
            return .idle
        }
    }

    static func writeSnapshot(_ value: SharedTransportSnapshot, reloadWidgets: Bool = true) {
        var published = value
        published.publishedAt = Date()

        guard let data = try? JSONEncoder().encode(published) else { return }

        if let url = snapshotURL {
            do {
                try data.write(
                    to: url,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: url.path
                )
            } catch {
                // UserDefaults is a second independent App Group transport below.
            }
        }

        defaults?.set(data, forKey: snapshotKey)
        defaults?.synchronize()

        guard reloadWidgets else { return }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            // Only two controls exist; unconditional reload is intentional. It avoids
            // suppressing a refresh because a stale prior cross-process copy happened
            // to compare equal to the newly-published state.
            ControlCenter.shared.reloadControls(ofKind: ControlKinds.microphone)
            ControlCenter.shared.reloadControls(ofKind: ControlKinds.receive)
        }
        #endif
    }
}

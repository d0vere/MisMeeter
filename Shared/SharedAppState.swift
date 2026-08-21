import Foundation
import os
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
    /// Wall-clock publication time for diagnostics and stale-state inspection.
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

    /// Enforces invariants shared by every presentation surface. A stopped transport
    /// can never remain visually muted, and a fully idle snapshot has no start time.
    func normalized() -> SharedTransportSnapshot {
        var value = self
        if !value.isStreaming { value.isMuted = false }
        if !value.isReceiving { value.isReceiveMuted = false }
        if !value.isStreaming && !value.isReceiving { value.startedAt = nil }
        return value
    }
}

enum SharedAppState {
    static let appGroup = "group.dev.mismeeter.app"

    /// v4 uses one authoritative App Group file. Previous releases mirrored the
    /// same snapshot through both a file and UserDefaults, which created a genuine
    /// split-brain failure mode when the two caches advanced at different times.
    private static let snapshotFilename = "transport-state-v4.json"

    private struct WriterState: Sendable {
        var writes: UInt64 = 0
    }

    private static let writerLock = OSAllocatedUnfairLock(
        initialState: WriterState()
    )

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    static func readSnapshot() -> SharedTransportSnapshot {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SharedTransportSnapshot.self, from: data)
        else {
            return .idle
        }
        return snapshot.normalized()
    }

    static func writeSnapshot(_ value: SharedTransportSnapshot, reloadWidgets: Bool = true) {
        var published = value.normalized()
        published.publishedAt = Date()

        guard let url = snapshotURL,
              let data = try? JSONEncoder().encode(published)
        else {
            return
        }

        writerLock.withLock { writer in
            do {
                try data.write(
                    to: url,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: url.path
                )
                writer.writes &+= 1
            } catch {
                // An atomic write failure leaves the last complete snapshot intact.
            }
        }

        guard reloadWidgets else { return }

        #if canImport(WidgetKit)
        // Control Center is intentionally NOT reloaded here. A Control interaction
        // is automatically reloaded by iOS after its AppIntent returns; triggering
        // another reload mid-intent races that lifecycle. Runtime-originated control
        // changes reload the specific control through SharedControlStateStore.
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

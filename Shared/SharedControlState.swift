import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Minimal state used exclusively by iOS system Controls.
///
/// A ControlWidgetToggle needs exactly one authoritative Boolean. v4 therefore
/// persists only the two mute bits plus ordering metadata. Transport running/idle
/// status, preset metadata and ActivityKit state cannot influence the toggle value.
/// The app is the only writer; the widget extension performs atomic reads only.
struct SharedControlState: Codable, Equatable, Sendable {
    var txMuted: Bool
    var rxMuted: Bool
    var revision: UInt64
    var publishedAt: Date

    static let idle = SharedControlState(
        txMuted: false,
        rxMuted: false,
        revision: 0,
        publishedAt: .distantPast
    )
}

enum SharedControlStateStore {
    static let appGroup = SharedAppState.appGroup

    /// New kinds intentionally reset the Control Center registration for v4.
    /// iOS caches control templates by kind; a major-release kind avoids carrying
    /// stale 3.x state/template archives into the rebuilt implementation.
    enum Kinds {
        static let receive = "dev.mismeeter.app.control.v4.receiveMute"
        static let microphone = "dev.mismeeter.app.control.v4.microphoneMute"
    }

    private static let filename = "control-state-v4.json"

    private struct WriterState: Sendable {
        var lastRevision: UInt64 = 0
    }

    /// Serializes app-process writes and rejects an older publication that happens
    /// to finish after a newer one. Widget processes have their own lock instance,
    /// but never write this file.
    private static let writerLock = OSAllocatedUnfairLock(
        initialState: WriterState()
    )

    private static var stateURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename, isDirectory: false)
    }

    static func read() -> SharedControlState {
        guard let url = stateURL,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SharedControlState.self, from: data)
        else {
            return .idle
        }
        return state
    }

    static func write(_ state: SharedControlState) {
        guard let url = stateURL,
              let data = try? JSONEncoder().encode(state)
        else {
            return
        }

        writerLock.withLock { writer in
            guard state.revision >= writer.lastRevision else { return }

            do {
                try data.write(
                    to: url,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: url.path
                )
                writer.lastRevision = state.revision
            } catch {
                // Keep the previous valid atomic file. The next runtime publication
                // retries automatically; never replace good state with partial data.
            }
        }
    }

    #if canImport(WidgetKit)
    static func reloadMicrophoneControl() {
        guard #available(iOS 18.0, *) else { return }
        ControlCenter.shared.reloadControls(ofKind: Kinds.microphone)
    }

    static func reloadReceiveControl() {
        guard #available(iOS 18.0, *) else { return }
        ControlCenter.shared.reloadControls(ofKind: Kinds.receive)
    }

    #endif
}

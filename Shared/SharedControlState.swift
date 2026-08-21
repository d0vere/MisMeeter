import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Authoritative presentation state for the two iOS system Controls.
///
/// v4.0.1 stores both transport liveness and mute state. The mute Bool remains the
/// value driven by ControlWidgetToggle; the active Bool is presentation metadata so
/// Control Center can distinguish ACTIVE from IDLE after state changes originating
/// from the app, widgets, Live Activity, start/stop, or process teardown.
struct SharedControlState: Codable, Equatable, Sendable {
    var txActive: Bool
    var txMuted: Bool
    var rxActive: Bool
    var rxMuted: Bool
    var revision: UInt64
    var publishedAt: Date

    static let idle = SharedControlState(
        txActive: false,
        txMuted: false,
        rxActive: false,
        rxMuted: false,
        revision: 0,
        publishedAt: .distantPast
    )

    /// Never expose a logically impossible highlighted mute state for an inactive
    /// transport, even if a future migration reads malformed or partial data.
    var normalized: SharedControlState {
        var value = self
        if !value.txActive { value.txMuted = false }
        if !value.rxActive { value.rxMuted = false }
        return value
    }
}

enum SharedControlStateStore {
    static let appGroup = SharedAppState.appGroup

    /// Keep the v4 kinds stable so existing Control Center placements survive the
    /// 4.0.0 -> 4.0.1 update. Only the state schema changes.
    enum Kinds {
        static let receive = "dev.mismeeter.app.control.v4.receiveMute"
        static let microphone = "dev.mismeeter.app.control.v4.microphoneMute"
    }

    private static let filename = "control-state-v4.0.1.json"

    private struct WriterState: Sendable {
        var lastRevision: UInt64 = 0
    }

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
        return state.normalized
    }

    /// Writes the state atomically and returns whether the new state became the
    /// authoritative on-disk value. A reload is only requested after a successful
    /// publication so the extension can never be asked to render half-written data.
    @discardableResult
    static func write(_ state: SharedControlState) -> Bool {
        guard let url = stateURL,
              let data = try? JSONEncoder().encode(state.normalized)
        else {
            return false
        }

        return writerLock.withLock { writer in
            guard state.revision >= writer.lastRevision else { return false }

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
                return true
            } catch {
                // Preserve the last complete state. The next runtime state mutation
                // republishes automatically.
                return false
            }
        }
    }

    #if canImport(WidgetKit)
    /// External state changes (app UI, Live Activity, widget, start/stop) must ask
    /// Control Center to reload. Apple documents this as the supported mechanism
    /// for reflecting app-originated state changes in configured controls.
    ///
    /// The two MisMeeter controls are intentionally reloaded together. Their state
    /// is one atomic snapshot, and keeping them on the same revision eliminates
    /// cross-control visual skew at negligible cost.
    static func reloadAllControls() {
        guard #available(iOS 18.0, *) else { return }

        if Thread.isMainThread {
            ControlCenter.shared.reloadAllControls()
        } else {
            // Make the reload request part of the completed state transaction. This
            // matters for short-lived AppIntent executions that may be suspended as
            // soon as perform() returns.
            DispatchQueue.main.sync {
                ControlCenter.shared.reloadAllControls()
            }
        }
    }
    #endif
}

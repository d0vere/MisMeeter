import ActivityKit
import Foundation
import os

private actor MisMeeterLiveActivityCoordinator {
    private let logger = Logger(subsystem: "dev.mismeeter.app", category: "LiveActivity")
    private var latestRevision: UInt64 = 0

    /// Reconciles ActivityKit from a versioned runtime snapshot. Revision ordering
    /// prevents an older async task (for example Start immediately followed by Stop)
    /// from recreating or overwriting a newer Live Activity state.
    func reconcile(
        state: MicActivityAttributes.ContentState,
        sessionName: String,
        active: Bool
    ) async {
        let revision = state.presentationRevision ?? 0
        guard revision >= latestRevision else { return }
        latestRevision = revision

        let activities = Activity<MicActivityAttributes>.activities
        guard active else {
            let idleState = MicActivityAttributes.ContentState(
                snapshot: .idle,
                presentationRevision: revision
            )
            for activity in activities {
                await activity.end(
                    ActivityContent(state: idleState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            return
        }

        if let primary = activities.first {
            await primary.update(ActivityContent(state: state, staleDate: nil))
            for duplicate in activities.dropFirst() {
                await duplicate.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(
                attributes: MicActivityAttributes(sessionName: sessionName),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

final class MisMeeterRuntime {
    static let shared = MisMeeterRuntime()

    private let stateQueue = DispatchQueue(label: "dev.mismeeter.runtime.state")
    private let commandLock = NSLock()
    private let statePublicationLock = NSLock()
    private let transmitter: VBANTransmitter
    private let microphone: MicrophoneEngine
    private let receiver: VBANReceiver
    private let liveActivities = MisMeeterLiveActivityCoordinator()

    private var _isMuted = false
    private var _isStreaming = false
    private var _isReceiving = false
    private var _isReceiveMuted = false
    private var _startedAt: Date?
    private var _preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )
    private var _receivePreset = VBANReceivePreset(
        name: "Receive",
        port: 6980,
        streamName: "MisMeeterRX"
    )
    private var _activityPresentationRevision: UInt64 = 0

    private struct RuntimeSnapshot {
        let isStreaming: Bool
        let isMuted: Bool
        let isReceiving: Bool
        let isReceiveMuted: Bool
        let startedAt: Date?
        let preset: VBANPreset
        let receivePreset: VBANReceivePreset
    }

    /// meter, callbackFrames, ioBufferDuration, maxCallbackGapMS
    var onMicrophoneDiagnostics: ((Float, Int, Double, Double) -> Void)?
    /// packetsSent, sendErrors, captureRate, transmittedRate, maxSendGapMS
    var onTransmitterDiagnostics: ((UInt64, UInt64, Double, Double, Double) -> Void)?
    var onVoiceProcessingState: ((Bool) -> Void)?
    /// received, rejected, lost, bufferedFrames, underflows, primed, playbackRate, targetMS
    var onReceiverDiagnostics: ((UInt64, UInt64, UInt64, Int, UInt64, Bool, Float, Double) -> Void)?
    var onTransportSnapshotChange: ((SharedTransportSnapshot) -> Void)?

    private init() {
        let tx = VBANTransmitter()
        transmitter = tx
        microphone = MicrophoneEngine(transmitter: tx)
        receiver = VBANReceiver()

        microphone.onDiagnostics = { [weak self] meter, frames, duration, maxGap in
            self?.onMicrophoneDiagnostics?(meter, frames, duration, maxGap)
        }
        microphone.onVoiceProcessingState = { [weak self] value in
            self?.onVoiceProcessingState?(value)
        }

        transmitter.onDiagnostics = { [weak self] sent, errors, captureRate, txRate, maxGap in
            self?.onTransmitterDiagnostics?(sent, errors, captureRate, txRate, maxGap)
        }

        receiver.onDiagnostics = { [weak self] received, rejected, lost, buffered, underflows, primed, rate, targetMS in
            self?.onReceiverDiagnostics?(
                received,
                rejected,
                lost,
                buffered,
                underflows,
                primed,
                rate,
                targetMS
            )
        }

    }

    var isMuted: Bool { stateQueue.sync { _isMuted } }
    var isStreaming: Bool { stateQueue.sync { _isStreaming } }
    var isReceiving: Bool { stateQueue.sync { _isReceiving } }
    var isReceiveMuted: Bool { stateQueue.sync { _isReceiveMuted } }
    var startedAt: Date? { stateQueue.sync { _startedAt } }
    var activePreset: VBANPreset { stateQueue.sync { _preset } }
    var activeReceivePreset: VBANReceivePreset { stateQueue.sync { _receivePreset } }

    var gainDB: Float {
        get { microphone.gainDB }
        set { microphone.gainDB = newValue }
    }

    func start(
        preset: VBANPreset,
        gainDB: Float,
        captureMode: CaptureMode
    ) async throws {
        try withCommandLock {
            guard !isStreaming else { return }

            stateQueue.sync {
                _preset = preset
                _isMuted = false
            }
            microphone.gainDB = gainDB
            transmitter.configure(preset: preset)
            transmitter.setMuted(false)

            // Changing AVAudioSession from RX-only (.playback) to duplex
            // (.playAndRecord) underneath a running AVAudioEngine can leave the
            // input Audio Unit in an invalid/codec state on real devices. Quiesce
            // RX first, establish the duplex session + microphone, then rebuild RX.
            let hadReceiver = isReceiving
            let savedReceivePreset = activeReceivePreset
            let savedReceiveMute = isReceiveMuted
            if hadReceiver {
                receiver.stop(deactivateSession: false)
            }

            do {
                try transmitter.start()
                try microphone.start(captureMode: captureMode)
                if hadReceiver {
                    try receiver.start(
                        preset: savedReceivePreset,
                        transmitterAlreadyActive: true
                    )
                    receiver.setOutputMuted(savedReceiveMute)
                }
            } catch {
                microphone.stop(deactivateSession: false)
                transmitter.stop()

                if hadReceiver {
                    // Best-effort restoration of the pre-existing RX session.
                    try? receiver.start(
                        preset: savedReceivePreset,
                        transmitterAlreadyActive: false
                    )
                    receiver.setOutputMuted(savedReceiveMute)
                } else {
                    AudioSessionCoordinator.shared.deactivateIfPossible()
                }

                publishSharedState(status: error.localizedDescription)
                publishControlState(reloadControls: true)
                throw error
            }

            stateQueue.sync {
                _isStreaming = true
                if _startedAt == nil { _startedAt = Date() }
            }
            publishSharedState(status: isReceiving ? "Duplex live" : "Live")
            publishControlState(reloadControls: true)
        }

        await reconcileLiveActivity()
    }

    func stop() async {
        withCommandLock {
            guard isStreaming else {
                publishSharedState(status: isReceiving ? receiveStatusText : "Ready")
                publishControlState(reloadControls: true)
                return
            }

            let keepAudioSession = isReceiving
            stateQueue.sync {
                _isStreaming = false
                _isMuted = false
                if !_isReceiving { _startedAt = nil }
            }

            // Publish the intended state before lower-level teardown.
            publishSharedState(status: keepAudioSession ? receiveStatusText : "Ready")
            publishControlState(reloadControls: true)
            microphone.stop(deactivateSession: !keepAudioSession)
            transmitter.stop()
            if keepAudioSession {
                receiver.refreshAudioSession(transmitterActive: false)
            }
        }

        await reconcileLiveActivity()
    }

    func startReceiving(preset: VBANReceivePreset) throws {
        try withCommandLock {
            guard !isReceiving else { return }

            do {
                try receiver.start(
                    preset: preset,
                    transmitterAlreadyActive: isStreaming
                )
            } catch {
                receiver.stop(deactivateSession: !isStreaming)
                stateQueue.sync {
                    _isReceiving = false
                    _isReceiveMuted = false
                    if !_isStreaming { _startedAt = nil }
                }
                publishSharedState(status: error.localizedDescription)
                publishControlState(reloadControls: true)
                Task { await reconcileLiveActivity() }
                throw error
            }

            stateQueue.sync {
                _receivePreset = preset
                _isReceiving = true
                _isReceiveMuted = false
                if _startedAt == nil { _startedAt = Date() }
            }
            publishSharedState(status: isStreaming ? "Duplex live" : "Listening")
            publishControlState(reloadControls: true)
        }
        Task { await reconcileLiveActivity() }
    }

    func stopReceiving() {
        withCommandLock {
            guard isReceiving else {
                publishSharedState(status: isStreaming ? currentStatusText : "Ready")
                publishControlState(reloadControls: true)
                return
            }

            let keepAudioSession = isStreaming
            stateQueue.sync {
                _isReceiving = false
                _isReceiveMuted = false
                if !_isStreaming { _startedAt = nil }
            }

            let status = keepAudioSession
                ? (isMuted ? "Microphone muted" : "Live")
                : "Ready"
            publishSharedState(status: status)
            publishControlState(reloadControls: true)
            receiver.stop(deactivateSession: !keepAudioSession)
        }
        Task { await reconcileLiveActivity() }
    }

    func stopAll() async {
        withCommandLock {
            let hadTX = isStreaming
            let hadRX = isReceiving

            stateQueue.sync {
                _isStreaming = false
                _isMuted = false
                _isReceiving = false
                _isReceiveMuted = false
                _startedAt = nil
            }
            publishSharedState(status: "Ready")
            publishControlState(reloadControls: true)

            if hadTX {
                microphone.stop(deactivateSession: false)
                transmitter.stop()
            }
            if hadRX {
                receiver.stop(deactivateSession: false)
            }
            AudioSessionCoordinator.shared.deactivateIfPossible()
        }
        await reconcileLiveActivity()
    }

    @discardableResult
    func toggleMuted() -> Bool {
        let value: Bool? = withCommandLock {
            let newValue: Bool? = stateQueue.sync {
                guard _isStreaming else { return nil }
                _isMuted.toggle()
                return _isMuted
            }
            guard let newValue else { return nil }

            transmitter.setMuted(newValue)
            publishSharedState(
                status: newValue ? "Microphone muted" : (isReceiving ? "Duplex live" : "Live")
            )
            publishControlState(reloadControls: true)
            return newValue
        }

        if value != nil {
            Task { await syncLiveActivity() }
        }
        return value ?? false
    }

    /// ControlWidget entry point. WidgetKit reloads the interacted control after
    /// `perform()` returns, so this path persists state but does not manually reload it.
    func setMutedFromSystemControl(_ value: Bool) async {
        let applied = withCommandLock {
            applyMutedSynchronously(value, reloadControls: false)
        }
        if applied {
            await syncLiveActivity()
        }
    }

    @discardableResult
    func toggleReceiveMuted() -> Bool {
        let value: Bool? = withCommandLock {
            let newValue: Bool? = stateQueue.sync {
                guard _isReceiving else { return nil }
                _isReceiveMuted.toggle()
                return _isReceiveMuted
            }
            guard let newValue else { return nil }

            receiver.setOutputMuted(newValue)
            publishSharedState(
                status: newValue ? "Receive muted" : (isStreaming ? "Duplex live" : "Listening")
            )
            publishControlState(reloadControls: true)
            return newValue
        }

        if value != nil {
            Task { await syncLiveActivity() }
        }
        return value ?? false
    }

    func setReceiveMutedFromSystemControl(_ value: Bool) async {
        let applied = withCommandLock {
            applyReceiveMutedSynchronously(value, reloadControls: false)
        }
        if applied {
            await syncLiveActivity()
        }
    }

    func refreshSystemControls() {
        publishSharedState(status: currentStatusText)
        SharedControlStateStore.reloadAllConfiguredControls()
    }

    /// Invalidates cached Control Center templates without publishing runtime state.
    /// Used during process launch because a LiveActivityIntent may launch the app in
    /// the background. Publishing a new runtime's default idle state at that moment
    /// would race the intent and make the system toggle snap back.
    func invalidateSystemControlsOnly() {
        SharedControlStateStore.reloadAllConfiguredControls()
    }

    /// Best-effort cleanup for normal process termination. iOS does not guarantee
    /// this callback for every force-quit/background scenario.
    func prepareForProcessTermination() {
        withCommandLock {
            stateQueue.sync {
                _isStreaming = false
                _isMuted = false
                _isReceiving = false
                _isReceiveMuted = false
                _startedAt = nil
            }
            publishSharedState(status: "Ready")
            publishControlState(reloadControls: true)
        }
    }

    func cleanupOrphanedLiveActivitiesIfIdle() async {
        guard !isStreaming && !isReceiving else { return }
        await reconcileLiveActivity()
    }

    func syncLiveActivity() async {
        await reconcileLiveActivity()
    }

    private func applyMutedSynchronously(_ value: Bool, reloadControls: Bool) -> Bool {
        let applied = stateQueue.sync { () -> Bool in
            guard _isStreaming else { return false }
            _isMuted = value
            return true
        }
        guard applied else {
            publishSharedState(status: currentStatusText)
            return false
        }

        transmitter.setMuted(value)
        publishSharedState(
            status: value ? "Microphone muted" : (isReceiving ? "Duplex live" : "Live")
        )
        publishControlState(reloadControls: reloadControls)
        return true
    }

    private func applyReceiveMutedSynchronously(_ value: Bool, reloadControls: Bool) -> Bool {
        let applied = stateQueue.sync { () -> Bool in
            guard _isReceiving else { return false }
            _isReceiveMuted = value
            return true
        }
        guard applied else {
            publishSharedState(status: currentStatusText)
            return false
        }

        receiver.setOutputMuted(value)
        publishSharedState(
            status: value ? "Receive muted" : (isStreaming ? "Duplex live" : "Listening")
        )
        publishControlState(reloadControls: reloadControls)
        return true
    }

    private func reconcileLiveActivity() async {
        let runtime = runtimeSnapshot()
        let active = runtime.isStreaming || runtime.isReceiving
        let state = activityState(runtime: runtime, status: statusText(for: runtime))
        let sessionName = runtime.isStreaming
            ? runtime.preset.sanitizedStreamName
            : runtime.receivePreset.sanitizedStreamName
        await liveActivities.reconcile(
            state: state,
            sessionName: sessionName,
            active: active
        )
    }

    private func statusText(for runtime: RuntimeSnapshot) -> String {
        if runtime.isStreaming && runtime.isReceiving {
            return (runtime.isMuted || runtime.isReceiveMuted)
                ? "Live · muted channel"
                : "Duplex live"
        }
        if runtime.isStreaming {
            return runtime.isMuted ? "Microphone muted" : "Live"
        }
        if runtime.isReceiving {
            return runtime.isReceiveMuted ? "Receive muted" : "Listening"
        }
        return "Ready"
    }

    private var receiveStatusText: String {
        let runtime = runtimeSnapshot()
        return runtime.isReceiveMuted ? "Receive muted" : "Listening"
    }

    private var currentStatusText: String {
        statusText(for: runtimeSnapshot())
    }

    private func activityState(
        runtime: RuntimeSnapshot,
        status: String
    ) -> MicActivityAttributes.ContentState {
        let revision = stateQueue.sync {
            _activityPresentationRevision &+= 1
            return _activityPresentationRevision
        }
        return MicActivityAttributes.ContentState(
            snapshot: sharedSnapshot(runtime: runtime, status: status),
            presentationRevision: revision
        )
    }

    private func runtimeSnapshot() -> RuntimeSnapshot {
        stateQueue.sync {
            RuntimeSnapshot(
                isStreaming: _isStreaming,
                isMuted: _isStreaming && _isMuted,
                isReceiving: _isReceiving,
                isReceiveMuted: _isReceiving && _isReceiveMuted,
                startedAt: (_isStreaming || _isReceiving) ? _startedAt : nil,
                preset: _preset,
                receivePreset: _receivePreset
            )
        }
    }

    private func sharedSnapshot(status: String) -> SharedTransportSnapshot {
        sharedSnapshot(runtime: runtimeSnapshot(), status: status)
    }

    private func sharedSnapshot(
        runtime: RuntimeSnapshot,
        status: String
    ) -> SharedTransportSnapshot {
        let txPreset = runtime.preset
        let rxPreset = runtime.receivePreset
        let primaryPresetName = runtime.isStreaming
            ? txPreset.name
            : (runtime.isReceiving ? rxPreset.name : txPreset.name)
        let primaryDestination = runtime.isStreaming
            ? txPreset.destinationLabel
            : (runtime.isReceiving ? "RX · UDP \(rxPreset.port)" : "Not connected")
        let primaryStreamName = runtime.isStreaming
            ? txPreset.sanitizedStreamName
            : rxPreset.sanitizedStreamName

        return SharedTransportSnapshot(
            isStreaming: runtime.isStreaming,
            isMuted: runtime.isMuted,
            isReceiving: runtime.isReceiving,
            isReceiveMuted: runtime.isReceiveMuted,
            presetName: primaryPresetName,
            sendPresetName: txPreset.name,
            receivePresetName: rxPreset.name,
            destination: primaryDestination,
            streamName: primaryStreamName,
            startedAt: runtime.startedAt,
            status: status
        )
    }

    private func publishControlState(reloadControls: Bool = false) {
        guard reloadControls else { return }
        SharedControlStateStore.reloadMisMeeterControls()
    }

    private func publishSharedState(status: String) {
        statePublicationLock.lock()
        let snapshot = sharedSnapshot(status: status)
        SharedAppState.writeSnapshot(snapshot)
        statePublicationLock.unlock()
        onTransportSnapshotChange?(snapshot)
    }

    @discardableResult
    private func withCommandLock<T>(_ body: () throws -> T) rethrows -> T {
        commandLock.lock()
        defer { commandLock.unlock() }
        return try body()
    }
}

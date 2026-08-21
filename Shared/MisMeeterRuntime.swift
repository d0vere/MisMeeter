import ActivityKit
import Foundation

final class MisMeeterRuntime {
    static let shared = MisMeeterRuntime()

    private let stateQueue = DispatchQueue(label: "dev.mismeeter.runtime.state")
    private let transmitter: VBANTransmitter
    private let microphone: MicrophoneEngine
    private let receiver: VBANReceiver
    private let txMuteCommandLock = NSLock()
    private let rxMuteCommandLock = NSLock()
    /// Serializes snapshot capture + App Group publication. Capturing after acquiring
    /// this lock prevents an older callback from writing state fields captured before
    /// a newer runtime mutation.
    private let statePublicationLock = NSLock()

    private var _isMuted = false
    private var _isStreaming = false
    private var _isReceiving = false
    private var _isReceiveMuted = false
    private var _startedAt: Date?
    private var _preset = VBANPreset(name: "Preset 1", host: "", port: 6980, streamName: "MisMeeter")
    private var _receivePreset = VBANReceivePreset(name: "Receive", port: 6980, streamName: "MisMeeterRX")
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

    var onStatusChange: ((String) -> Void)?
    var onMeter: ((Float) -> Void)?
    var onBufferLevel: ((Int) -> Void)?
    var onAudioDiagnostics: ((Int, Double) -> Void)?
    var onCaptureGap: ((Double) -> Void)?
    var onCaptureLabDiagnostics: ((Double, UInt64, UInt64, UInt64, UInt64, Int, UInt64, Double, UInt64, UInt64, Int) -> Void)?
    var onUnderruns: ((UInt64) -> Void)?
    var onPacketsSent: ((UInt64) -> Void)?
    var onPrimedChange: ((Bool) -> Void)?
    var onPLLStats: ((Double, Double, Double, Double, UInt64) -> Void)?
    var onVoiceProcessingState: ((Bool) -> Void)?
    var onReceiverStatus: ((String) -> Void)?
    var onReceiverDiagnostics: ((UInt64, UInt64, UInt64, Int, UInt64, Bool, Float, Double) -> Void)?
    var onTransportMode: ((TransportState, Int, Int, Double) -> Void)?
    /// Emitted after every authoritative transport snapshot is persisted. This keeps
    /// the in-app SwiftUI state synchronized with changes initiated from system
    /// Controls, not only with changes initiated by the app UI.
    var onTransportSnapshotChange: ((SharedTransportSnapshot) -> Void)?

    private init() {
        let tx = VBANTransmitter()
        transmitter = tx
        microphone = MicrophoneEngine(transmitter: tx)
        receiver = VBANReceiver()

        microphone.onMeter = { [weak self] in self?.onMeter?($0) }
        microphone.onAudioDiagnostics = { [weak self] in self?.onAudioDiagnostics?($0, $1) }
        microphone.onCaptureLabDiagnostics = { [weak self] maxGapMS, over10, over15, over25, over50, buffered, overruns, txWakeGap, txLate, txDropped, txTarget in
            self?.onCaptureGap?(maxGapMS)
            self?.onCaptureLabDiagnostics?(maxGapMS, over10, over15, over25, over50, buffered, overruns, txWakeGap, txLate, txDropped, txTarget)
        }
        microphone.onVoiceProcessingState = { [weak self] in self?.onVoiceProcessingState?($0) }

        transmitter.onStateChange = { [weak self] value in
            self?.onStatusChange?(value)
            self?.publishSharedState(status: value)
        }
        transmitter.onBufferLevel = { [weak self] in self?.onBufferLevel?($0) }
        transmitter.onUnderruns = { [weak self] in self?.onUnderruns?($0) }
        transmitter.onPacketsSent = { [weak self] in self?.onPacketsSent?($0) }
        transmitter.onPrimedChange = { [weak self] in self?.onPrimedChange?($0) }
        transmitter.onPLLStats = { [weak self] in self?.onPLLStats?($0, $1, $2, $3, $4) }
        transmitter.onTransportMode = { [weak self] in self?.onTransportMode?($0, $1, $2, $3) }

        receiver.onStatus = { [weak self] value in
            self?.onReceiverStatus?(value)
            self?.publishSharedState(status: value)
        }
        receiver.onDiagnostics = { [weak self] received, rejected, lost, buffered, underflows, primed, rate, targetMS in
            self?.onReceiverDiagnostics?(received, rejected, lost, buffered, underflows, primed, rate, targetMS)
        }

        publishSharedState(status: "Ready")
        publishControlState()
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
        transmissionMode: VBANTransmissionMode,
        captureMode: CaptureMode
    ) async throws {
        stateQueue.sync {
            _preset = preset
            _isMuted = false
        }
        microphone.gainDB = gainDB
        transmitter.configure(preset: preset, transmissionMode: transmissionMode)
        transmitter.setMuted(false)

        do {
            try transmitter.start()
            try microphone.start(captureMode: captureMode)
        } catch {
            transmitter.stop()
            publishSharedState(status: error.localizedDescription)
            throw error
        }

        stateQueue.sync {
            _isStreaming = true
            if _startedAt == nil { _startedAt = Date() }
        }
        if isReceiving {
            receiver.refreshAudioSession(transmitterActive: true)
        }
        publishSharedState(status: isReceiving ? "Duplex live" : "Live")
        publishControlState(reloadControls: true)

        // ActivityKit is the only Dynamic Island / Lock Screen presentation surface.
        // There is deliberately no legacy system-media session: that avoids the
        // duplicate Dynamic Island presentation entirely.
        await ensureLiveActivity()
    }

    func stop() async {
        guard isStreaming else {
            await updateActivityLifecycle()
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

        // Publish the intended transport state before lower-level stop callbacks fire.
        // This prevents transient snapshots such as "Stopped" + isStreaming=true.
        publishSharedState(status: keepAudioSession ? receiveStatusText : "Ready")
        publishControlState(reloadControls: true)
        microphone.stop(deactivateSession: !keepAudioSession)
        transmitter.stop()
        if keepAudioSession {
            receiver.refreshAudioSession(transmitterActive: false)
        }
        await updateActivityLifecycle()
    }

    func startReceiving(preset: VBANReceivePreset) throws {
        do {
            try receiver.start(preset: preset, transmitterAlreadyActive: isStreaming)
        } catch {
            // VBANReceiver.start() intentionally tears down any previous receiver
            // before rebuilding the socket/audio graph. If rebuilding fails, the
            // runtime must not keep advertising the old RX session as active.
            stateQueue.sync {
                _isReceiving = false
                _isReceiveMuted = false
                if !_isStreaming { _startedAt = nil }
            }
            publishSharedState(status: error.localizedDescription)
            publishControlState(reloadControls: true)
            Task { await updateActivityLifecycle() }
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
        Task { await ensureLiveActivity() }
    }

    func stopReceiving() {
        let keepAudioSession = isStreaming
        stateQueue.sync {
            _isReceiving = false
            _isReceiveMuted = false
            if !_isStreaming { _startedAt = nil }
        }

        let status = keepAudioSession ? (isMuted ? "Microphone muted" : "Live") : "Ready"
        publishSharedState(status: status)
        publishControlState(reloadControls: true)
        receiver.stop(deactivateSession: !keepAudioSession)
        Task { await updateActivityLifecycle() }
    }

    func stopAll() async {
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
        onStatusChange?("Ready")
        onReceiverStatus?("Ready")
        await endLiveActivity()
    }

    @discardableResult
    func toggleMuted() -> Bool {
        txMuteCommandLock.lock()
        let newValue: Bool? = stateQueue.sync {
            guard _isStreaming else { return nil }
            _isMuted.toggle()
            return _isMuted
        }
        guard let value = newValue else {
            txMuteCommandLock.unlock()
            return false
        }
        transmitter.setMuted(value)
        publishSharedState(status: value ? "Microphone muted" : (isReceiving ? "Duplex live" : "Live"))
        txMuteCommandLock.unlock()
        publishControlState(reloadControls: true)

        Task { await syncLiveActivity() }
        return value
    }

    /// App/UI entry point. Runtime state is committed and persisted before asking
    /// iOS to reload both configured MisMeeter Controls from the same revision.
    func setMuted(_ value: Bool) {
        txMuteCommandLock.lock()
        let applied = stateQueue.sync { () -> Bool in
            guard _isStreaming else { return false }
            _isMuted = value
            return true
        }
        guard applied else {
            txMuteCommandLock.unlock()
            return
        }
        transmitter.setMuted(value)
        publishSharedState(status: value ? "Microphone muted" : (isReceiving ? "Duplex live" : "Live"))
        txMuteCommandLock.unlock()
        publishControlState(reloadControls: true)

        Task { await syncLiveActivity() }
    }

    /// ControlWidget entry point. Do not request a ControlCenter reload here:
    /// WidgetKit automatically reloads the interacted control after perform()
    /// returns. The state file is written synchronously before that return.
    func setMutedFromSystemControl(_ value: Bool) async {
        let applied = applyMutedFromSystemControlSynchronously(value)
        if applied {
            await syncLiveActivity()
        }
    }

    private func applyMutedFromSystemControlSynchronously(_ value: Bool) -> Bool {
        txMuteCommandLock.lock()
        defer { txMuteCommandLock.unlock() }

        let applied = stateQueue.sync { () -> Bool in
            guard _isStreaming else { return false }
            _isMuted = value
            return true
        }
        guard applied else {
            // The interaction may have started from a stale system surface. Persist
            // the authoritative inactive state before perform() returns; WidgetKit's
            // automatic post-intent refresh will then read the provider again.
            publishSharedState(status: currentStatusText)
            return false
        }

        transmitter.setMuted(value)
        publishSharedState(
            status: value ? "Microphone muted" : (isReceiving ? "Duplex live" : "Live")
        )
        publishControlState()
        return true
    }

    @discardableResult
    func toggleReceiveMuted() -> Bool {
        rxMuteCommandLock.lock()
        // Commit the authoritative state before touching the receiver. The receiver
        // emits an onStatus callback synchronously from setOutputMuted().
        let newValue: Bool? = stateQueue.sync {
            guard _isReceiving else { return nil }
            _isReceiveMuted.toggle()
            return _isReceiveMuted
        }
        guard let value = newValue else {
            rxMuteCommandLock.unlock()
            return false
        }
        receiver.setOutputMuted(value)
        publishSharedState(status: value ? "Receive muted" : (isStreaming ? "Duplex live" : "Listening"))
        rxMuteCommandLock.unlock()
        publishControlState(reloadControls: true)

        Task { await syncLiveActivity() }
        return value
    }

    /// App/UI entry point.
    func setReceiveMuted(_ value: Bool) {
        rxMuteCommandLock.lock()
        let applied = stateQueue.sync { () -> Bool in
            guard _isReceiving else { return false }
            _isReceiveMuted = value
            return true
        }
        guard applied else {
            rxMuteCommandLock.unlock()
            return
        }
        receiver.setOutputMuted(value)
        publishSharedState(status: value ? "Receive muted" : (isStreaming ? "Duplex live" : "Listening"))
        rxMuteCommandLock.unlock()
        publishControlState(reloadControls: true)

        Task { await syncLiveActivity() }
    }

    /// ControlWidget entry point; see setMutedFromSystemControl(_:).
    func setReceiveMutedFromSystemControl(_ value: Bool) async {
        let applied = applyReceiveMutedFromSystemControlSynchronously(value)
        if applied {
            await syncLiveActivity()
        }
    }

    private func applyReceiveMutedFromSystemControlSynchronously(_ value: Bool) -> Bool {
        rxMuteCommandLock.lock()
        defer { rxMuteCommandLock.unlock() }

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
        publishControlState()
        return true
    }

    func beginLockTransition() {
        transmitter.beginLockTransition()
        microphone.setBackgroundMode(false)
        if isStreaming || isReceiving {
            Task { await syncLiveActivity() }
        }
    }

    func enterBackgroundTransport() {
        transmitter.enterBackground()
        microphone.setBackgroundMode(true)
        if isStreaming || isReceiving {
            Task { await syncLiveActivity() }
        }
    }

    func enterForegroundTransport() {
        transmitter.enterForeground()
        microphone.setBackgroundMode(false)
        if isStreaming || isReceiving {
            Task { await syncLiveActivity() }
        }
    }

    // Shared snapshots are output-only: they describe what the runtime actually
    // applied. System Controls invoke exact SetValueIntent values in the app process;
    // there is intentionally no snapshot -> runtime reconciliation loop.

    func refreshSystemControls() {
        // Re-publish the canonical transport snapshot first, then invalidate the
        // exact Control kinds. Their providers re-read this snapshot on refresh.
        publishSharedState(status: currentStatusText)
        publishControlState(reloadControls: true)
    }

    /// Best-effort lifecycle cleanup for normal process termination. iOS does not
    /// guarantee a termination callback for every force-quit/background scenario,
    /// but whenever the callback is delivered we publish IDLE before the process exits.
    func prepareForProcessTermination() {
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

    func cleanupOrphanedLiveActivitiesIfIdle() async {
        guard !isStreaming && !isReceiving else { return }
        await endLiveActivity()
    }

    func syncLiveActivity() async {
        guard isStreaming || isReceiving else {
            await endLiveActivity()
            return
        }
        let state = activityState(status: currentStatusText)
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func ensureLiveActivity() async {
        let preset = activePreset
        let state = activityState(status: currentStatusText)
        if let activity = Activity<MicActivityAttributes>.activities.first {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(
                attributes: MicActivityAttributes(sessionName: preset.sanitizedStreamName),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("MISMEETER: Live Activity error: \(error)")
        }
    }

    private func updateActivityLifecycle() async {
        if isStreaming || isReceiving {
            await ensureLiveActivity()
        } else {
            await endLiveActivity()
        }
    }

    private func endLiveActivity() async {
        let state = MicActivityAttributes.ContentState(snapshot: .idle)
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private var receiveStatusText: String {
        let runtime = runtimeSnapshot()
        return runtime.isReceiveMuted ? "Receive muted" : "Listening"
    }

    private var currentStatusText: String {
        let runtime = runtimeSnapshot()
        if runtime.isStreaming && runtime.isReceiving {
            return (runtime.isMuted || runtime.isReceiveMuted) ? "Live · muted channel" : "Duplex live"
        }
        if runtime.isStreaming { return runtime.isMuted ? "Microphone muted" : "Live" }
        if runtime.isReceiving { return runtime.isReceiveMuted ? "Receive muted" : "Listening" }
        return "Ready"
    }

    private func activityState(status: String) -> MicActivityAttributes.ContentState {
        var snapshot = sharedSnapshot(status: status)
        snapshot.status = status
        let revision = stateQueue.sync {
            _activityPresentationRevision &+= 1
            return _activityPresentationRevision
        }
        return MicActivityAttributes.ContentState(
            snapshot: snapshot,
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
        let runtime = runtimeSnapshot()
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

    /// Invalidates the system Controls after an external runtime mutation.
    ///
    /// There is intentionally no second Control-specific state file. The
    /// authoritative state was already persisted by `publishSharedState(status:)`
    /// before this method is called. A SetValueIntent interaction passes `false`
    /// here and relies on WidgetKit's automatic post-perform reload instead.
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
}

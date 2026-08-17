import ActivityKit
import Foundation

final class MisMeeterRuntime {
    static let shared = MisMeeterRuntime()

    private let stateQueue = DispatchQueue(label: "dev.mismeeter.runtime.state")
    private let transmitter: VBANTransmitter
    private let microphone: MicrophoneEngine
    private let receiver: VBANReceiver
    private let controlObserver = SharedControlObserver()

    private var _isMuted = false
    private var _isStreaming = false
    private var _isReceiving = false
    private var _isReceiveMuted = false
    private var _startedAt: Date?
    private var _preset = VBANPreset(name: "Preset 1", host: "", port: 6980, streamName: "MisMeeter")
    private var _receivePreset = VBANReceivePreset(name: "Receive", port: 6980, streamName: "MisMeeterRX", bufferMS: 100)

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

        controlObserver.start { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleMicrophoneMute:
                _ = self.toggleMuted()
            case .toggleReceiveMute:
                _ = self.toggleReceiveMuted()
            case .stopAll:
                Task { await self.stopAll() }
            }
        }
        publishSharedState(status: "Ready")
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
        if isReceiving { AudioSessionCoordinator.shared.forceSpeaker() }
        publishSharedState(status: isReceiving ? "Duplex live" : "Live")
        await ensureLiveActivity()
    }

    func stop() async {
        guard isStreaming else {
            await updateActivityLifecycle()
            publishSharedState(status: isReceiving ? receiveStatusText : "Ready")
            return
        }
        let keepAudioSession = isReceiving
        microphone.stop(deactivateSession: !keepAudioSession)
        transmitter.stop()
        stateQueue.sync {
            _isStreaming = false
            _isMuted = false
            if !_isReceiving { _startedAt = nil }
        }
        publishSharedState(status: keepAudioSession ? receiveStatusText : "Ready")
        await updateActivityLifecycle()
    }

    func startReceiving(preset: VBANReceivePreset) throws {
        try receiver.start(preset: preset, transmitterAlreadyActive: isStreaming)
        stateQueue.sync {
            _receivePreset = preset
            _isReceiving = true
            _isReceiveMuted = false
            if _startedAt == nil { _startedAt = Date() }
        }
        publishSharedState(status: isStreaming ? "Duplex live" : "Listening")
        Task { await ensureLiveActivity() }
    }

    func stopReceiving() {
        let keepAudioSession = isStreaming
        receiver.stop(deactivateSession: !keepAudioSession)
        stateQueue.sync {
            _isReceiving = false
            _isReceiveMuted = false
            if !_isStreaming { _startedAt = nil }
        }
        publishSharedState(status: keepAudioSession ? (isMuted ? "Microphone muted" : "Live") : "Ready")
        Task { await updateActivityLifecycle() }
    }

    func stopAll() async {
        let hadTX = isStreaming
        let hadRX = isReceiving
        if hadTX {
            microphone.stop(deactivateSession: false)
            transmitter.stop()
        }
        if hadRX {
            receiver.stop(deactivateSession: false)
        }
        AudioSessionCoordinator.shared.deactivateIfPossible()
        stateQueue.sync {
            _isStreaming = false
            _isMuted = false
            _isReceiving = false
            _isReceiveMuted = false
            _startedAt = nil
        }
        SharedAppState.writeSnapshot(.idle)
        onStatusChange?("Ready")
        onReceiverStatus?("Ready")
        await endLiveActivity()
    }

    @discardableResult
    func toggleMuted() -> Bool {
        guard isStreaming else { return false }
        let value = stateQueue.sync {
            _isMuted.toggle()
            return _isMuted
        }
        transmitter.setMuted(value)
        publishSharedState(status: value ? "Microphone muted" : (isReceiving ? "Duplex live" : "Live"))
        Task { await syncLiveActivity() }
        return value
    }

    func setMuted(_ value: Bool) {
        guard isStreaming else { return }
        stateQueue.sync { _isMuted = value }
        transmitter.setMuted(value)
        publishSharedState(status: value ? "Microphone muted" : (isReceiving ? "Duplex live" : "Live"))
        Task { await syncLiveActivity() }
    }

    @discardableResult
    func toggleReceiveMuted() -> Bool {
        guard isReceiving else { return false }
        let value = receiver.toggleOutputMuted()
        stateQueue.sync { _isReceiveMuted = value }
        publishSharedState(status: value ? "Receive muted" : (isStreaming ? "Duplex live" : "Listening"))
        Task { await syncLiveActivity() }
        return value
    }

    func setReceiveMuted(_ value: Bool) {
        guard isReceiving else { return }
        receiver.setOutputMuted(value)
        stateQueue.sync { _isReceiveMuted = value }
        publishSharedState(status: value ? "Receive muted" : (isStreaming ? "Duplex live" : "Listening"))
        Task { await syncLiveActivity() }
    }

    func beginLockTransition() {
        transmitter.beginLockTransition()
        microphone.setBackgroundMode(false)
    }

    func enterBackgroundTransport() {
        transmitter.enterBackground()
        microphone.setBackgroundMode(true)
    }

    func enterForegroundTransport() {
        transmitter.enterForeground()
        microphone.setBackgroundMode(false)
    }

    func reconcileExternalControlState() async {
        let snapshot = SharedAppState.readSnapshot()
        if (isStreaming && !snapshot.isStreaming) || (isReceiving && !snapshot.isReceiving) {
            if !snapshot.isStreaming && !snapshot.isReceiving {
                await stopAll()
                return
            }
            if isStreaming && !snapshot.isStreaming { await stop() }
            if isReceiving && !snapshot.isReceiving { stopReceiving() }
        }
        if isStreaming && snapshot.isMuted != isMuted { setMuted(snapshot.isMuted) }
        if isReceiving && snapshot.isReceiveMuted != isReceiveMuted { setReceiveMuted(snapshot.isReceiveMuted) }
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
        isReceiveMuted ? "Receive muted" : "Listening"
    }

    private var currentStatusText: String {
        if isStreaming && isReceiving { return (isMuted || isReceiveMuted) ? "Live · muted channel" : "Duplex live" }
        if isStreaming { return isMuted ? "Microphone muted" : "Live" }
        if isReceiving { return isReceiveMuted ? "Receive muted" : "Listening" }
        return "Ready"
    }

    private func activityState(status: String) -> MicActivityAttributes.ContentState {
        var snapshot = sharedSnapshot(status: status)
        snapshot.status = status
        return MicActivityAttributes.ContentState(snapshot: snapshot)
    }

    private func sharedSnapshot(status: String) -> SharedTransportSnapshot {
        let txPreset = activePreset
        let rxPreset = activeReceivePreset
        let primaryPresetName = isStreaming ? txPreset.name : (isReceiving ? rxPreset.name : txPreset.name)
        let primaryDestination = isStreaming
            ? txPreset.destinationLabel
            : (isReceiving ? "RX · UDP \(rxPreset.port)" : "Not connected")
        let primaryStreamName = isStreaming ? txPreset.sanitizedStreamName : rxPreset.sanitizedStreamName

        return SharedTransportSnapshot(
            isStreaming: isStreaming,
            isMuted: isMuted,
            isReceiving: isReceiving,
            isReceiveMuted: isReceiveMuted,
            presetName: primaryPresetName,
            sendPresetName: txPreset.name,
            receivePresetName: rxPreset.name,
            destination: primaryDestination,
            streamName: primaryStreamName,
            startedAt: startedAt,
            status: status
        )
    }

    private func publishSharedState(status: String) {
        SharedAppState.writeSnapshot(sharedSnapshot(status: status))
    }
}

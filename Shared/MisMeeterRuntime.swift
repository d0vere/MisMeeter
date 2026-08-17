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
    private var _startedAt: Date?
    private var _preset = VBANPreset(name: "Preset 1", host: "", port: 6980, streamName: "MisMeeter")

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
            case .toggleMute:
                _ = self.toggleMuted()
            case .stopStreaming:
                Task { await self.stop() }
            }
        }
        publishSharedState(status: "Ready")
    }

    var isMuted: Bool { stateQueue.sync { _isMuted } }
    var isStreaming: Bool { stateQueue.sync { _isStreaming } }
    var isReceiving: Bool { stateQueue.sync { _isReceiving } }
    var startedAt: Date? { stateQueue.sync { _startedAt } }
    var activePreset: VBANPreset { stateQueue.sync { _preset } }

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
            _startedAt = Date()
        }
        if isReceiving { AudioSessionCoordinator.shared.forceSpeaker() }
        publishSharedState(status: "Live")
        await updateOrStartLiveActivity()
    }

    func stop() async {
        guard isStreaming else {
            await endLiveActivity()
            publishSharedState(status: isReceiving ? "Listening" : "Ready")
            return
        }
        let keepAudioSession = isReceiving
        microphone.stop(deactivateSession: !keepAudioSession)
        transmitter.stop()
        stateQueue.sync {
            _isStreaming = false
            _isMuted = false
            _startedAt = nil
        }
        publishSharedState(status: keepAudioSession ? "Listening" : "Ready")
        await endLiveActivity()
    }

    func startReceiving(preset: VBANReceivePreset) throws {
        try receiver.start(preset: preset, transmitterAlreadyActive: isStreaming)
        stateQueue.sync { _isReceiving = true }
        publishSharedState(status: isStreaming ? "Duplex live" : "Listening")
        Task { await syncLiveActivity() }
    }

    func stopReceiving() {
        let keepAudioSession = isStreaming
        receiver.stop(deactivateSession: !keepAudioSession)
        stateQueue.sync { _isReceiving = false }
        publishSharedState(status: keepAudioSession ? "Live" : "Ready")
        Task { await syncLiveActivity() }
    }

    @discardableResult
    func toggleMuted() -> Bool {
        guard isStreaming else { return false }
        let value = stateQueue.sync {
            _isMuted.toggle()
            return _isMuted
        }
        transmitter.setMuted(value)
        publishSharedState(status: value ? "Muted" : "Live")
        Task { await syncLiveActivity() }
        return value
    }

    func setMuted(_ value: Bool) {
        guard isStreaming else { return }
        stateQueue.sync { _isMuted = value }
        transmitter.setMuted(value)
        publishSharedState(status: value ? "Muted" : "Live")
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

    func cleanupOrphanedLiveActivitiesIfIdle() async {
        guard !isStreaming else { return }
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: activityState(status: "Stopped"), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    func syncLiveActivity() async {
        let state = activityState(status: isMuted ? "Muted" : (isStreaming ? "Live" : "Stopped"))
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func updateOrStartLiveActivity() async {
        let preset = activePreset
        let state = activityState(status: "Live")
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

    private func endLiveActivity() async {
        let state = activityState(status: "Stopped")
        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private func activityState(status: String) -> MicActivityAttributes.ContentState {
        let preset = activePreset
        return MicActivityAttributes.ContentState(
            isMuted: isMuted,
            isStreaming: isStreaming,
            isReceiving: isReceiving,
            destinationLabel: preset.destinationLabel,
            presetLabel: preset.name,
            startedAt: startedAt,
            statusLabel: status
        )
    }

    private func publishSharedState(status: String) {
        let preset = activePreset
        SharedAppState.writeSnapshot(
            SharedTransportSnapshot(
                isStreaming: isStreaming,
                isMuted: isMuted,
                isReceiving: isReceiving,
                presetName: preset.name,
                destination: preset.destinationLabel,
                streamName: preset.sanitizedStreamName,
                startedAt: startedAt,
                status: status
            )
        )
    }
}

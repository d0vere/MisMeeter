import ActivityKit
import Foundation

final class MisMeeterRuntime {
    static let shared = MisMeeterRuntime()

    private let stateQueue = DispatchQueue(
        label: "dev.mismeeter.runtime.state"
    )

    private let transmitter: VBANTransmitter
    private let microphone: MicrophoneEngine
    private let receiver: VBANReceiver

    private var _isMuted = false
    private var _isStreaming = false
    private var _isReceiving = false
    private var _preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

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

        microphone.onMeter = { [weak self] value in
            self?.onMeter?(value)
        }

        microphone.onAudioDiagnostics = { [weak self] frames, duration in
            self?.onAudioDiagnostics?(frames, duration)
        }

        microphone.onCaptureLabDiagnostics = { [weak self] maxGapMS, over10, over15, over25, over50, buffered, overruns, txWakeGap, txLate, txCatchUp, txTarget in
            self?.onCaptureGap?(maxGapMS)
            self?.onCaptureLabDiagnostics?(
                maxGapMS,
                over10,
                over15,
                over25,
                over50,
                buffered,
                overruns,
                txWakeGap,
                txLate,
                txCatchUp,
                txTarget
            )
        }

        microphone.onVoiceProcessingState = { [weak self] enabled in
            self?.onVoiceProcessingState?(enabled)
        }

        transmitter.onStateChange = { [weak self] value in
            self?.onStatusChange?(value)
        }

        transmitter.onBufferLevel = { [weak self] count in
            self?.onBufferLevel?(count)
        }

        transmitter.onUnderruns = { [weak self] count in
            self?.onUnderruns?(count)
        }

        transmitter.onPacketsSent = { [weak self] count in
            self?.onPacketsSent?(count)
        }

        transmitter.onPrimedChange = { [weak self] value in
            self?.onPrimedChange?(value)
        }
        transmitter.onPLLStats = { [weak self] targetMS, captureHz, txHz, lateMS, catchUps in
            self?.onPLLStats?(targetMS, captureHz, txHz, lateMS, catchUps)
        }

        transmitter.onTransportMode = { [weak self] state, batchSize, bufferedSamples, maxGapMS in
            self?.onTransportMode?(state, batchSize, bufferedSamples, maxGapMS)
        }

        receiver.onStatus = { [weak self] value in
            self?.onReceiverStatus?(value)
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

    var isMuted: Bool {
        stateQueue.sync { _isMuted }
    }

    var isStreaming: Bool {
        stateQueue.sync { _isStreaming }
    }

    var isReceiving: Bool {
        stateQueue.sync { _isReceiving }
    }

    var activePreset: VBANPreset {
        stateQueue.sync { _preset }
    }

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

        transmitter.configure(
            preset: preset,
            transmissionMode: transmissionMode
        )
        transmitter.setMuted(false)
        transmitter.start()

        do {
            try microphone.start(
                captureMode: captureMode
            )
        } catch {
            transmitter.stop()
            throw error
        }

        stateQueue.sync {
            _isStreaming = true
        }

        if isReceiving {
            AudioSessionCoordinator.shared
                .forceSpeaker()
        }

        await updateOrStartLiveActivity()
    }

    func stop() async {
        let keepAudioSession = isReceiving

        microphone.stop(
            deactivateSession: !keepAudioSession
        )

        transmitter.stop()

        stateQueue.sync {
            _isStreaming = false
        }

        await endLiveActivity()
    }

    func startReceiving(
        preset: VBANReceivePreset
    ) throws {
        try receiver.start(
            preset: preset,
            transmitterAlreadyActive: isStreaming
        )

        stateQueue.sync {
            _isReceiving = true
        }
    }

    func stopReceiving() {
        let keepAudioSession = isStreaming

        receiver.stop(
            deactivateSession: !keepAudioSession
        )

        stateQueue.sync {
            _isReceiving = false
        }
    }

    @discardableResult
    func toggleMuted() -> Bool {
        let value = stateQueue.sync {
            _isMuted.toggle()
            return _isMuted
        }

        transmitter.setMuted(value)
        return value
    }

    func setMuted(_ value: Bool) {
        stateQueue.sync {
            _isMuted = value
        }
        transmitter.setMuted(value)
    }

    func beginLockTransition() {
        transmitter.beginLockTransition()
    }

    func enterBackgroundTransport() {
        transmitter.enterBackground()
    }

    func enterForegroundTransport() {
        transmitter.enterForeground()
    }

    func cleanupOrphanedLiveActivitiesIfIdle() async {
        guard !isStreaming else { return }

        let finalState = MicActivityAttributes.ContentState(
            isMuted: true,
            isStreaming: false,
            destinationLabel: "Stopped",
            presetLabel: "Stopped"
        )

        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(
                    state: finalState,
                    staleDate: nil
                ),
                dismissalPolicy: .immediate
            )
        }
    }

    func syncLiveActivity() async {
        let preset = activePreset

        let state = MicActivityAttributes.ContentState(
            isMuted: isMuted,
            isStreaming: isStreaming,
            destinationLabel: preset.destinationLabel,
            presetLabel: preset.name
        )

        for activity in Activity<MicActivityAttributes>.activities {
            await activity.update(
                ActivityContent(
                    state: state,
                    staleDate: nil
                )
            )
        }
    }

    private func updateOrStartLiveActivity() async {
        let preset = activePreset

        let state = MicActivityAttributes.ContentState(
            isMuted: isMuted,
            isStreaming: isStreaming,
            destinationLabel: preset.destinationLabel,
            presetLabel: preset.name
        )

        if let activity = Activity<MicActivityAttributes>.activities.first {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        do {
            _ = try Activity.request(
                attributes: MicActivityAttributes(
                    sessionName: preset.sanitizedStreamName
                ),
                content: ActivityContent(
                    state: state,
                    staleDate: nil
                ),
                pushType: nil
            )
        } catch {
            print("MISMEETER: Live Activity error: \(error)")
        }
    }

    private func endLiveActivity() async {
        let preset = activePreset

        let state = MicActivityAttributes.ContentState(
            isMuted: true,
            isStreaming: false,
            destinationLabel: "Stopped",
            presetLabel: preset.name
        )

        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(
                    state: state,
                    staleDate: nil
                ),
                dismissalPolicy: .immediate
            )
        }
    }
}

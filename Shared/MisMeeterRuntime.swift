import ActivityKit
import Foundation

final class MisMeeterRuntime {
    static let shared = MisMeeterRuntime()

    private let stateQueue = DispatchQueue(
        label: "dev.mismeeter.runtime.state"
    )

    private let transmitter: VBANTransmitter
    private let microphone: MicrophoneEngine

    private var _isMuted = false
    private var _isStreaming = false
    private var _preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

    var onStatusChange: ((String) -> Void)?
    var onMeter: ((Float) -> Void)?
    var onBufferLevel: ((Int) -> Void)?
    var onPacketsSent: ((UInt64) -> Void)?
    var onAudioDiagnostics: ((Int, Double) -> Void)?

    private init() {
        let tx = VBANTransmitter()
        transmitter = tx
        microphone = MicrophoneEngine(transmitter: tx)

        microphone.onMeter = { [weak self] value in
            self?.onMeter?(value)
        }

        microphone.onAudioDiagnostics = { [weak self] frames, duration in
            self?.onAudioDiagnostics?(frames, duration)
        }

        transmitter.onStateChange = { [weak self] value in
            self?.onStatusChange?(value)
        }

        transmitter.onBufferLevel = { [weak self] count in
            self?.onBufferLevel?(count)
        }

        transmitter.onPacketsSent = { [weak self] count in
            self?.onPacketsSent?(count)
        }
    }

    var isMuted: Bool {
        stateQueue.sync { _isMuted }
    }

    var isStreaming: Bool {
        stateQueue.sync { _isStreaming }
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
        gainDB: Float
    ) async throws {
        stateQueue.sync {
            _preset = preset
            _isMuted = false
        }

        microphone.gainDB = gainDB

        transmitter.configure(preset: preset)
        transmitter.setMuted(false)
        transmitter.start()

        do {
            try microphone.start()
        } catch {
            transmitter.stop()
            throw error
        }

        stateQueue.sync {
            _isStreaming = true
        }

        await updateOrStartLiveActivity()
    }

    func stop() async {
        microphone.stop()
        transmitter.stop()

        stateQueue.sync {
            _isStreaming = false
        }

        await endLiveActivity()
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

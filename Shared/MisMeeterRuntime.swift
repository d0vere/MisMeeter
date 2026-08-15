import ActivityKit
import Foundation

final class MisMeeterRuntime {
    static let shared = MisMeeterRuntime()

    private let stateQueue = DispatchQueue(label: "dev.mismeeter.runtime.state")
    private let transmitter: VBANTransmitter
    private let microphone: MicrophoneEngine

    private var _isMuted = false
    private var _isStreaming = false

    var onStatusChange: ((String) -> Void)?
    var onMeter: ((Float) -> Void)?

    private init() {
        let tx = VBANTransmitter()
        transmitter = tx
        microphone = MicrophoneEngine(transmitter: tx)

        microphone.isMutedProvider = { [weak self] in
            self?.isMuted ?? true
        }

        microphone.onMeter = { [weak self] value in
            self?.onMeter?(value)
        }

        transmitter.onStateChange = { [weak self] value in
            self?.onStatusChange?(value)
        }
    }

    var isMuted: Bool { stateQueue.sync { _isMuted } }
    var isStreaming: Bool { stateQueue.sync { _isStreaming } }

    func start(host: String, port: UInt16, streamName: String) async throws {
        transmitter.configure(host: host, port: port, streamName: streamName)
        transmitter.start()

        do {
            try microphone.start()
        } catch {
            transmitter.stop()
            throw error
        }

        stateQueue.sync {
            _isStreaming = true
            _isMuted = false
        }

        await updateOrStartLiveActivity(destinationLabel: "\(host):\(port)")
    }

    func stop() async {
        microphone.stop()
        transmitter.stop()

        stateQueue.sync { _isStreaming = false }
        await endLiveActivity()
    }

    @discardableResult
    func toggleMuted() -> Bool {
        stateQueue.sync {
            _isMuted.toggle()
            return _isMuted
        }
    }

    func syncLiveActivity(destinationLabel: String? = nil) async {
        let destination = destinationLabel ?? "\(transmitter.host):\(transmitter.port)"
        let state = MicActivityAttributes.ContentState(
            isMuted: isMuted,
            isStreaming: isStreaming,
            destinationLabel: destination
        )

        for activity in Activity<MicActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func updateOrStartLiveActivity(destinationLabel: String) async {
        let state = MicActivityAttributes.ContentState(
            isMuted: isMuted,
            isStreaming: isStreaming,
            destinationLabel: destinationLabel
        )

        if let activity = Activity<MicActivityAttributes>.activities.first {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        do {
            _ = try Activity.request(
                attributes: MicActivityAttributes(sessionName: "VBAN Microphone"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("MISMEETER: Live Activity start error: \(error)")
        }
    }

    private func endLiveActivity() async {
        let state = MicActivityAttributes.ContentState(
            isMuted: true,
            isStreaming: false,
            destinationLabel: "Stopped"
        )

        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}

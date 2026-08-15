import Foundation
import Network

final class VBANTransmitter {
    private let queue = DispatchQueue(
        label: "dev.mismeeter.vban.tx",
        qos: .userInteractive
    )

    private var connection: NWConnection?
    private var pacingTimer: DispatchSourceTimer?
    private let fifo = SampleFIFO()

    private var frameCounter: UInt32 = 0
    private var muted = false

    private(set) var preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

    var onStateChange: ((String) -> Void)?
    var onBufferLevel: ((Int) -> Void)?

    func configure(preset: VBANPreset) {
        queue.sync {
            self.preset = preset
        }
    }

    func start() {
        queue.async {
            self.stopLocked()

            let host = self.preset.host.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !host.isEmpty,
                  let nwPort = NWEndpoint.Port(rawValue: self.preset.port) else {
                self.onStateChange?("Invalid VBAN destination")
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .udp
            )

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    self.onStateChange?("VBAN ready")
                    self.startPacingTimer()
                case .preparing:
                    self.onStateChange?("Connecting…")
                case .waiting(let error):
                    self.onStateChange?("Waiting: \(error.localizedDescription)")
                case .failed(let error):
                    self.onStateChange?("Network error: \(error.localizedDescription)")
                case .cancelled:
                    self.onStateChange?("Stopped")
                default:
                    break
                }
            }

            self.connection = connection
            self.frameCounter = 0
            self.fifo.clear()
            connection.start(queue: self.queue)
        }
    }

    func stop() {
        queue.async {
            self.stopLocked()
        }
    }

    func setMuted(_ value: Bool) {
        queue.async {
            self.muted = value
        }
    }

    /// Audio callbacks only append samples.
    /// UDP packet timing is deliberately decoupled from AVAudioEngine callback timing.
    func enqueue(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }

        queue.async {
            self.fifo.append(samples)

            // Prevent runaway latency if the app/network gets stalled.
            let maxBufferedSamples = VBANPacket.samplesPerPacket * 12
            while self.fifo.count > maxBufferedSamples {
                _ = self.fifo.pop(VBANPacket.samplesPerPacket)
            }

            self.onBufferLevel?(self.fifo.count)
        }
    }

    private func startPacingTimer() {
        pacingTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)

        let nanoseconds = Int(
            VBANPacket.packetDurationSeconds * 1_000_000_000
        )

        timer.schedule(
            deadline: .now(),
            repeating: .nanoseconds(nanoseconds),
            leeway: .microseconds(250)
        )

        timer.setEventHandler { [weak self] in
            self?.sendNextPacket()
        }

        pacingTimer = timer
        timer.resume()
    }

    private func sendNextPacket() {
        guard let connection else { return }

        let samples: [Int16]

        if muted {
            // Consume buffered audio while muted so unmute resumes "now",
            // not from stale audio accumulated seconds earlier.
            _ = fifo.pop(min(fifo.count, VBANPacket.samplesPerPacket))
            samples = [Int16](repeating: 0, count: VBANPacket.samplesPerPacket)
        } else if let block = fifo.pop(VBANPacket.samplesPerPacket) {
            samples = block
        } else {
            // Underrun: keep VBAN clock continuous instead of producing a network gap.
            samples = [Int16](repeating: 0, count: VBANPacket.samplesPerPacket)
        }

        let packet = VBANPacket.make(
            samples: samples,
            streamName: preset.sanitizedStreamName,
            frameCounter: frameCounter
        )

        frameCounter &+= 1

        connection.send(
            content: packet,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.onStateChange?(
                        "UDP send error: \(error.localizedDescription)"
                    )
                }
            }
        )

        onBufferLevel?(fifo.count)
    }

    private func stopLocked() {
        pacingTimer?.setEventHandler {}
        pacingTimer?.cancel()
        pacingTimer = nil

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        fifo.clear()
        frameCounter = 0
    }
}

import Foundation
import Network

final class VBANTransmitter {
    private let queue = DispatchQueue(
        label: "dev.mismeeter.vban.tx",
        qos: .userInteractive
    )

    private var connection: NWConnection?
    private let fifo = SampleFIFO()

    private var frameCounter: UInt32 = 0
    private var muted = false
    private var packetsSent: UInt64 = 0

    private(set) var preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

    var onStateChange: ((String) -> Void)?
    var onBufferLevel: ((Int) -> Void)?
    var onPacketsSent: ((UInt64) -> Void)?

    func configure(preset: VBANPreset) {
        queue.sync {
            self.preset = preset
        }
    }

    func start() {
        queue.async {
            self.stopLocked()

            let host = self.preset.host
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !host.isEmpty,
                  let nwPort = NWEndpoint.Port(rawValue: self.preset.port) else {
                self.onStateChange?("Invalid VBAN destination")
                return
            }

            // VBAN is real-time UDP audio. interactiveVoice gives the system
            // the correct scheduling / QoS hint for a low-delay constant-rate flow.
            let parameters = NWParameters.udp
            parameters.serviceClass = .interactiveVoice

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: parameters
            )

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    self.onStateChange?("VBAN ready")
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
            self.packetsSent = 0
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

    /// v0.5 deliberately does NOT pace packets using a separate software timer.
    ///
    /// VBAN defines the sender as the audio clock master. We therefore derive
    /// network timing directly from the microphone sample stream. If iOS gives
    /// us 512/1024 frames at once, sending 2/4 x 256-sample packets as a short
    /// burst is valid VBAN behaviour and is explicitly expected by receivers
    /// such as VoiceMeeter.
    func enqueue(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }

        queue.async {
            guard self.connection != nil else { return }

            self.fifo.append(samples)

            // Drain every complete VBAN frame immediately.
            while let block = self.fifo.pop(VBANPacket.samplesPerPacket) {
                self.send(block)
            }

            self.onBufferLevel?(self.fifo.count)
        }
    }

    private func send(_ microphoneSamples: [Int16]) {
        guard let connection else { return }

        let outgoing: [Int16]

        if muted {
            outgoing = [Int16](
                repeating: 0,
                count: VBANPacket.samplesPerPacket
            )
        } else {
            outgoing = microphoneSamples
        }

        let packet = VBANPacket.make(
            samples: outgoing,
            streamName: preset.sanitizedStreamName,
            frameCounter: frameCounter
        )

        frameCounter &+= 1
        packetsSent &+= 1

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

        onPacketsSent?(packetsSent)
    }

    private func stopLocked() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        fifo.clear()
        frameCounter = 0
        packetsSent = 0
    }
}

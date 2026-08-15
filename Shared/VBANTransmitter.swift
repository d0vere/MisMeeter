import Foundation
import Network

final class VBANTransmitter {
    private let queue = DispatchQueue(
        label: "dev.mismeeter.vban.tx",
        qos: .userInteractive
    )

    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private let fifo = SampleFIFO()

    private var frameCounter: UInt32 = 0
    private var muted = false
    private var primed = false
    private var underruns: UInt64 = 0
    private var packetsSent: UInt64 = 0

    private(set) var preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

    private(set) var transmissionMode: VBANTransmissionMode = .balanced

    var onStateChange: ((String) -> Void)?
    var onBufferLevel: ((Int) -> Void)?
    var onUnderruns: ((UInt64) -> Void)?
    var onPacketsSent: ((UInt64) -> Void)?
    var onPrimedChange: ((Bool) -> Void)?

    func configure(
        preset: VBANPreset,
        transmissionMode: VBANTransmissionMode
    ) {
        queue.sync {
            self.preset = preset
            self.transmissionMode = transmissionMode
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
                    self.onStateChange?("Prebuffering audio…")
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
            self.underruns = 0
            self.packetsSent = 0
            self.primed = false
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

    /// Audio callbacks only feed the FIFO.
    /// We do NOT transmit directly from the callback because iOS can deliver
    /// ~100 ms chunks (4800 samples) even while hardware I/O is 5.33 ms.
    func enqueue(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }

        queue.async {
            guard self.connection != nil else { return }

            self.fifo.append(samples)

            if !self.primed,
               self.fifo.count >= self.transmissionMode.startBufferSamples {
                self.primed = true
                self.onPrimedChange?(true)
                self.onStateChange?("VBAN streaming")
                self.scheduleNextPacket(after: 0)
            }

            self.onBufferLevel?(self.fifo.count)
        }
    }

    /// One packet is scheduled at a time from an absolute-ish monotonic cadence.
    /// The interval is nudged by only a few tenths of a percent according to
    /// FIFO occupancy, compensating tiny clock mismatch while keeping output smooth.
    private func scheduleNextPacket(after overrideDelay: Double? = nil) {
        guard primed else { return }

        timer?.setEventHandler {}
        timer?.cancel()

        let baseInterval = VBANPacket.packetDurationSeconds
        let delay = overrideDelay ?? adaptiveInterval(base: baseInterval)

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(
            deadline: .now() + delay,
            leeway: .microseconds(50)
        )

        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendOnePacket()
            self.scheduleNextPacket()
        }

        timer = t
        t.resume()
    }

    private func adaptiveInterval(base: Double) -> Double {
        let target = Double(transmissionMode.targetBufferSamples)
        let current = Double(fifo.count)

        guard target > 0 else { return base }

        // Positive error = FIFO is too full -> transmit microscopically faster.
        // Negative error = FIFO is too empty -> transmit microscopically slower.
        let normalizedError = max(-1.0, min(1.0, (current - target) / target))
        let correction = normalizedError * transmissionMode.maxClockCorrection

        return base * (1.0 - correction)
    }

    private func sendOnePacket() {
        guard let connection else { return }

        let source: [Int16]

        if let block = fifo.pop(VBANPacket.samplesPerPacket) {
            source = block
        } else {
            // This should be rare once prebuffered. Keep VBAN's sample clock alive.
            source = [Int16](
                repeating: 0,
                count: VBANPacket.samplesPerPacket
            )
            underruns &+= 1
            onUnderruns?(underruns)
        }

        let outgoing: [Int16]

        if muted {
            outgoing = [Int16](
                repeating: 0,
                count: VBANPacket.samplesPerPacket
            )
        } else {
            outgoing = source
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
        onBufferLevel?(fifo.count)
    }

    private func stopLocked() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        fifo.clear()
        frameCounter = 0
        packetsSent = 0
        underruns = 0
        primed = false
        onPrimedChange?(false)
    }
}

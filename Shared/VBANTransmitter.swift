import Foundation
import Network

final class VBANTransmitter {
    private let queue = DispatchQueue(
        label: "dev.mismeeter.vban.tx",
        qos: .userInteractive
    )

    private var connection: NWConnection?
    private let fifo = SampleFIFO()
    private let clockEstimator = AudioClockEstimator()

    private var frameCounter: UInt32 = 0
    private var muted = false
    private var packetsSent: UInt64 = 0
    private var underruns: UInt64 = 0

    private var measuredCaptureRate: Double = 48_000
    private var measuredTXRate: Double = 48_000
    private var txWindowStartNS: UInt64?
    private var txSamplesInWindow: UInt64 = 0

    private var isBackground = false
    private var batchSize = 1

    // Four VBAN frames = 1024 samples = ~21.33 ms @ 48 kHz.
    // In background we intentionally keep at least one full batch ready.
    private let backgroundBatchSize = 4

    private(set) var preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

    var onStateChange: ((String) -> Void)?
    var onBufferLevel: ((Int) -> Void)?
    var onUnderruns: ((UInt64) -> Void)?
    var onPacketsSent: ((UInt64) -> Void)?
    var onPrimedChange: ((Bool) -> Void)?

    /// target ms, capture Hz, TX Hz, scheduler late ms, catch-up count
    var onPLLStats: ((Double, Double, Double, Double, UInt64) -> Void)?

    /// background?, current batch size, buffered samples
    var onTransportMode: ((Bool, Int, Int) -> Void)?

    func configure(
        preset: VBANPreset,
        transmissionMode: VBANTransmissionMode
    ) {
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
                  let port = NWEndpoint.Port(rawValue: self.preset.port) else {
                self.onStateChange?("Invalid VBAN destination")
                return
            }

            let parameters = NWParameters.udp
            parameters.serviceClass = .interactiveVoice

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: port,
                using: parameters
            )

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    self.onStateChange?("VBAN realtime ready")
                    self.onPrimedChange?(true)
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
            self.underruns = 0
            self.measuredCaptureRate = 48_000
            self.measuredTXRate = 48_000
            self.txWindowStartNS = nil
            self.txSamplesInWindow = 0
            self.clockEstimator.reset()
            self.fifo.clear()

            self.batchSize = self.isBackground
                ? self.backgroundBatchSize
                : 1

            connection.start(queue: self.queue)
            self.publishStats()
            self.publishTransportMode()
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

    func setBackgroundMode(_ background: Bool) {
        queue.async {
            guard self.isBackground != background else { return }

            self.isBackground = background
            self.batchSize = background
                ? self.backgroundBatchSize
                : 1

            self.onStateChange?(
                background
                    ? "VBAN background stable"
                    : "VBAN realtime ready"
            )

            // Do not throw away queued audio during the transition.
            // Foreground immediately drains all complete frames.
            self.drainAvailablePackets()
            self.publishTransportMode()
        }
    }

    /// The AVAudioSinkNode render callback is the master audio clock.
    ///
    /// Foreground:
    ///   every complete 256-sample frame is sent immediately.
    ///
    /// Background:
    ///   wait for 4 complete VBAN frames, then send the 4 UDP datagrams
    ///   consecutively from one serial-queue wakeup. This trades ~21 ms of
    ///   batching latency for much greater tolerance to background scheduling
    ///   and Wi-Fi power-management jitter.
    func enqueue(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }

        let captureNow = DispatchTime.now().uptimeNanoseconds

        queue.async {
            guard self.connection != nil else { return }

            if let rate = self.clockEstimator.addCapturedSamples(
                samples.count,
                nowNS: captureNow
            ) {
                self.measuredCaptureRate = rate
            }

            self.fifo.append(samples)
            self.drainAvailablePackets()
            self.onBufferLevel?(self.fifo.count)
            self.publishStats()
            self.publishTransportMode()
        }
    }

    private func drainAvailablePackets() {
        let requiredSamples =
            VBANPacket.samplesPerPacket * batchSize

        while fifo.count >= requiredSamples {
            var blocks: [[Int16]] = []
            blocks.reserveCapacity(batchSize)

            for _ in 0..<batchSize {
                guard let block = fifo.pop(
                    VBANPacket.samplesPerPacket
                ) else {
                    return
                }
                blocks.append(block)
            }

            // Deliberately perform all sends in the same queue execution window.
            for block in blocks {
                send(block)
            }
        }

        // In foreground, don't intentionally retain a complete VBAN frame.
        if !isBackground {
            while let block = fifo.pop(
                VBANPacket.samplesPerPacket
            ) {
                send(block)
            }
        }
    }

    private func send(_ source: [Int16]) {
        guard let connection else { return }

        let outgoing =
            muted
            ? [Int16](
                repeating: 0,
                count: VBANPacket.samplesPerPacket
            )
            : source

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

        updateTXRate(samples: VBANPacket.samplesPerPacket)
        onPacketsSent?(packetsSent)
    }

    private func updateTXRate(samples: Int) {
        let now = DispatchTime.now().uptimeNanoseconds

        if txWindowStartNS == nil {
            txWindowStartNS = now
            txSamplesInWindow = UInt64(samples)
            return
        }

        txSamplesInWindow += UInt64(samples)

        guard let start = txWindowStartNS else { return }
        let elapsed = now &- start

        guard elapsed >= 2_000_000_000 else { return }

        let seconds = Double(elapsed) / 1_000_000_000.0
        let rate = Double(txSamplesInWindow) / seconds

        if rate > 44_000 && rate < 52_000 {
            measuredTXRate =
                measuredTXRate * 0.82 +
                rate * 0.18
        }

        txWindowStartNS = now
        txSamplesInWindow = 0
    }

    private func publishStats() {
        onPLLStats?(
            0,
            measuredCaptureRate,
            measuredTXRate,
            0,
            0
        )
    }

    private func publishTransportMode() {
        onTransportMode?(
            isBackground,
            batchSize,
            fifo.count
        )
    }

    private func stopLocked() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        fifo.clear()
        clockEstimator.reset()

        frameCounter = 0
        packetsSent = 0
        underruns = 0
        measuredCaptureRate = 48_000
        measuredTXRate = 48_000
        txWindowStartNS = nil
        txSamplesInWindow = 0

        onPrimedChange?(false)
    }
}

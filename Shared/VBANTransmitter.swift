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

    private var transportState: TransportState = .foregroundRealtime
    private var batchSize = 1

    private var transitionStartNS: UInt64?
    private var backgroundEnteredNS: UInt64?

    private var lastSendNS: UInt64?
    private var maxSendGapMS: Double = 0
    private var recentMaxSendGapMS: Double = 0

    private var adaptationWindowStartNS: UInt64?
    private var stableBackgroundWindows = 0

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

    /// state, batch size, buffered samples, max send gap
    var onTransportMode: ((TransportState, Int, Int, Double) -> Void)?

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

            self.transportState = .foregroundRealtime
            self.batchSize = 1
            self.transitionStartNS = nil
            self.backgroundEnteredNS = nil

            self.lastSendNS = nil
            self.maxSendGapMS = 0
            self.recentMaxSendGapMS = 0
            self.adaptationWindowStartNS = nil
            self.stableBackgroundWindows = 0

            self.clockEstimator.reset()
            self.fifo.clear()

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

    /// Called for SwiftUI .inactive.
    /// We deliberately keep foreground packet behaviour during this phase.
    func beginLockTransition() {
        queue.async {
            guard self.transportState == .foregroundRealtime else { return }

            self.transportState = .lockTransition
            self.transitionStartNS = DispatchTime.now().uptimeNanoseconds
            self.batchSize = 1

            self.onStateChange?("VBAN lock transition")
            self.publishTransportMode()
        }
    }

    /// Called only when SwiftUI scenePhase is truly .background.
    func enterBackground() {
        queue.async {
            guard self.transportState != .backgroundStable else { return }

            self.transportState = .backgroundStable
            self.backgroundEnteredNS = DispatchTime.now().uptimeNanoseconds
            self.adaptationWindowStartNS = self.backgroundEnteredNS
            self.stableBackgroundWindows = 0

            // Start conservatively.
            self.batchSize = 4

            self.onStateChange?("VBAN background stable")
            self.publishTransportMode()
        }
    }

    func enterForeground() {
        queue.async {
            self.transportState = .foregroundRealtime
            self.batchSize = 1
            self.transitionStartNS = nil
            self.backgroundEnteredNS = nil
            self.adaptationWindowStartNS = nil
            self.stableBackgroundWindows = 0
            self.recentMaxSendGapMS = 0

            self.drainAvailablePackets()

            self.onStateChange?("VBAN realtime ready")
            self.publishTransportMode()
        }
    }

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
            self.adaptBackgroundBatchIfNeeded()

            self.onBufferLevel?(self.fifo.count)
            self.publishStats()
            self.publishTransportMode()
        }
    }

    private func drainAvailablePackets() {
        switch transportState {
        case .foregroundRealtime, .lockTransition:
            while let block = fifo.pop(
                VBANPacket.samplesPerPacket
            ) {
                send(block)
            }

        case .backgroundStable:
            let required =
                VBANPacket.samplesPerPacket * batchSize

            while fifo.count >= required {
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

                for block in blocks {
                    send(block)
                }
            }
        }
    }

    private func adaptBackgroundBatchIfNeeded() {
        guard transportState == .backgroundStable else { return }

        let now = DispatchTime.now().uptimeNanoseconds

        if adaptationWindowStartNS == nil {
            adaptationWindowStartNS = now
            return
        }

        guard let start = adaptationWindowStartNS,
              now &- start >= 5_000_000_000 else {
            return
        }

        // If background send gaps exceed ~35 ms, become more conservative.
        if recentMaxSendGapMS > 35 {
            if batchSize < 6 {
                batchSize = 6
            } else if batchSize < 8 {
                batchSize = 8
            }
            stableBackgroundWindows = 0
        } else if recentMaxSendGapMS < 24 {
            stableBackgroundWindows += 1

            // After 15 s of stable operation, reduce latency one step.
            if stableBackgroundWindows >= 3 {
                if batchSize > 6 {
                    batchSize = 6
                } else if batchSize > 4 {
                    batchSize = 4
                }
                stableBackgroundWindows = 0
            }
        } else {
            stableBackgroundWindows = 0
        }

        recentMaxSendGapMS = 0
        adaptationWindowStartNS = now

        publishTransportMode()
    }

    private func send(_ source: [Int16]) {
        guard let connection else { return }

        let now = DispatchTime.now().uptimeNanoseconds

        if let previous = lastSendNS {
            let gapMS =
                Double(now - previous) / 1_000_000.0

            maxSendGapMS = max(maxSendGapMS, gapMS)
            recentMaxSendGapMS = max(
                recentMaxSendGapMS,
                gapMS
            )
        }

        lastSendNS = now

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
            transportState,
            batchSize,
            fifo.count,
            maxSendGapMS
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

        transportState = .foregroundRealtime
        batchSize = 1
        transitionStartNS = nil
        backgroundEnteredNS = nil

        lastSendNS = nil
        maxSendGapMS = 0
        recentMaxSendGapMS = 0
        adaptationWindowStartNS = nil
        stableBackgroundWindows = 0

        onPrimedChange?(false)
    }
}

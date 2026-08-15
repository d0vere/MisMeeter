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
    private let clockEstimator = AudioClockEstimator()

    private var frameCounter: UInt32 = 0
    private var muted = false
    private var primed = false

    private var underruns: UInt64 = 0
    private var packetsSent: UInt64 = 0

    private var nextDeadlineNS: UInt64 = 0
    private var targetBufferSamples: Int = 7_200

    private var measuredCaptureRate: Double = 48_000
    private var effectiveTXRate: Double = 48_000

    private var recentMinimumFIFO = Int.max
    private var recentMaximumFIFO = 0
    private var lastAdaptationNS: UInt64 = 0
    private var lastUnderrunCount: UInt64 = 0
    private var stableWindows = 0

    private var schedulerLateMS: Double = 0
    private var catchUpPackets: UInt64 = 0

    private(set) var preset = VBANPreset(
        name: "Preset 1",
        host: "",
        port: 6980,
        streamName: "MisMeeter"
    )

    private(set) var transmissionMode: VBANTransmissionMode = .automatic

    var onStateChange: ((String) -> Void)?
    var onBufferLevel: ((Int) -> Void)?
    var onUnderruns: ((UInt64) -> Void)?
    var onPacketsSent: ((UInt64) -> Void)?
    var onPrimedChange: ((Bool) -> Void)?

    /// target latency ms, measured capture Hz, TX Hz, scheduler lateness ms, catch-up packet count
    var onPLLStats: ((Double, Double, Double, Double, UInt64) -> Void)?

    func configure(
        preset: VBANPreset,
        transmissionMode: VBANTransmissionMode
    ) {
        queue.sync {
            self.preset = preset
            self.transmissionMode = transmissionMode
            self.targetBufferSamples = transmissionMode.initialTargetSamples
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
            self.catchUpPackets = 0
            self.primed = false

            self.measuredCaptureRate = 48_000
            self.effectiveTXRate = 48_000
            self.targetBufferSamples = self.transmissionMode.initialTargetSamples

            self.recentMinimumFIFO = Int.max
            self.recentMaximumFIFO = 0
            self.lastAdaptationNS = 0
            self.lastUnderrunCount = 0
            self.stableWindows = 0
            self.schedulerLateMS = 0

            self.clockEstimator.reset()
            self.fifo.clear()

            connection.start(queue: self.queue)
            self.publishStats()
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

    /// Called from the audio side. The capture clock is measured from sample count / monotonic time.
    func enqueue(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }

        let now = DispatchTime.now().uptimeNanoseconds

        queue.async {
            guard self.connection != nil else { return }

            if let newRate = self.clockEstimator.addCapturedSamples(
                samples.count,
                nowNS: now
            ) {
                self.measuredCaptureRate = newRate
            }

            self.fifo.append(samples)

            self.recentMinimumFIFO = min(
                self.recentMinimumFIFO,
                self.fifo.count
            )
            self.recentMaximumFIFO = max(
                self.recentMaximumFIFO,
                self.fifo.count
            )

            if !self.primed,
               self.fifo.count >= self.transmissionMode.startBufferSamples {
                self.primed = true
                self.onPrimedChange?(true)
                self.onStateChange?("VBAN streaming")

                let start = DispatchTime.now().uptimeNanoseconds
                self.nextDeadlineNS = start
                self.lastAdaptationNS = start
                self.recentMinimumFIFO = self.fifo.count
                self.recentMaximumFIFO = self.fifo.count

                self.armTimer()
            }

            self.onBufferLevel?(self.fifo.count)
        }
    }

    private func armTimer() {
        guard primed else { return }

        timer?.setEventHandler {}
        timer?.cancel()

        let now = DispatchTime.now().uptimeNanoseconds
        let deadline = max(now, nextDeadlineNS)

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(
            deadline: DispatchTime(uptimeNanoseconds: deadline),
            leeway: .microseconds(20)
        )

        t.setEventHandler { [weak self] in
            self?.timerFired()
        }

        timer = t
        t.resume()
    }

    private func timerFired() {
        let now = DispatchTime.now().uptimeNanoseconds

        if now > nextDeadlineNS {
            schedulerLateMS = Double(now - nextDeadlineNS) / 1_000_000.0
        } else {
            schedulerLateMS = 0
        }

        // IMPORTANT:
        // Never reset nextDeadlineNS to "now".
        // A late wakeup must not permanently slow the stream.
        //
        // Send the packets that should already have gone out, but cap the burst.
        var sentThisWake = 0

        while now >= nextDeadlineNS,
              sentThisWake < transmissionMode.maxCatchUpBurst {
            sendOnePacket()

            if sentThisWake > 0 {
                catchUpPackets &+= 1
            }

            sentThisWake += 1
            nextDeadlineNS &+= packetIntervalNS()
        }

        // If we're still extremely late after the allowed burst, retain the clock phase.
        // The next wake will continue catching up instead of silently accumulating latency.
        updateController(nowNS: now)
        armTimer()
    }

    private func packetIntervalNS() -> UInt64 {
        // One VBAN frame = 256 samples.
        // Lock TX rate primarily to measured capture rate.
        let rate = max(44_000, min(52_000, effectiveTXRate))
        let seconds = Double(VBANPacket.samplesPerPacket) / rate
        return UInt64(seconds * 1_000_000_000.0)
    }

    private func updateController(nowNS: UInt64) {
        let current = fifo.count
        recentMinimumFIFO = min(recentMinimumFIFO, current)
        recentMaximumFIFO = max(recentMaximumFIFO, current)

        // PLL:
        // Base TX rate follows measured capture rate.
        // FIFO error then adds a small proportional trim.
        let target = max(256, targetBufferSamples)
        let normalizedError = Double(current - target) / Double(target)

        // Up to +/- 1.5% buffer correction, enough to remove accumulated queue delay
        // much faster than the old +/-3000 ppm limiter.
        let fifoTrim = max(-0.015, min(0.015, normalizedError * 0.010))

        let desiredRate = measuredCaptureRate * (1.0 + fifoTrim)

        // Smooth rate changes so pitch/timing never jumps.
        effectiveTXRate =
            effectiveTXRate * 0.985 +
            desiredRate * 0.015

        guard transmissionMode == .automatic else {
            publishStats()
            return
        }

        // Adapt target every 4 s.
        guard nowNS &- lastAdaptationNS >= 4_000_000_000 else {
            publishStats()
            return
        }

        let hadUnderrun = underruns != lastUnderrunCount
        let nearEmpty = recentMinimumFIFO < 512

        if hadUnderrun || nearEmpty {
            // Stability lost: add 50 ms immediately.
            targetBufferSamples = min(
                14_400,
                targetBufferSamples + 2_400
            )
            stableWindows = 0
        } else {
            stableWindows += 1

            // Reduce by 25 ms after 8 clean seconds.
            if stableWindows >= 2 {
                targetBufferSamples = max(
                    transmissionMode.minimumTargetSamples,
                    targetBufferSamples - 1_200
                )
                stableWindows = 0
            }
        }

        lastUnderrunCount = underruns
        recentMinimumFIFO = fifo.count
        recentMaximumFIFO = fifo.count
        lastAdaptationNS = nowNS

        publishStats()
    }

    private func publishStats() {
        let targetMS =
            Double(targetBufferSamples) /
            VBANPacket.sampleRate *
            1000.0

        onPLLStats?(
            targetMS,
            measuredCaptureRate,
            effectiveTXRate,
            schedulerLateMS,
            catchUpPackets
        )
    }

    private func sendOnePacket() {
        guard let connection else { return }

        let source: [Int16]

        if let block = fifo.pop(VBANPacket.samplesPerPacket) {
            source = block
        } else {
            source = [Int16](
                repeating: 0,
                count: VBANPacket.samplesPerPacket
            )

            underruns &+= 1
            onUnderruns?(underruns)
        }

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
        clockEstimator.reset()

        frameCounter = 0
        packetsSent = 0
        underruns = 0
        catchUpPackets = 0
        primed = false

        measuredCaptureRate = 48_000
        effectiveTXRate = 48_000
        schedulerLateMS = 0
        nextDeadlineNS = 0

        onPrimedChange?(false)
    }
}

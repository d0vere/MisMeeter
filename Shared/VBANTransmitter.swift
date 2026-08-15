import Foundation
import Network

final class VBANTransmitter {
    private let queue = DispatchQueue(label: "dev.mismeeter.vban.tx", qos: .userInteractive)
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private let fifo = SampleFIFO()

    private var frameCounter: UInt32 = 0
    private var muted = false, primed = false
    private var underruns: UInt64 = 0, packetsSent: UInt64 = 0
    private var nextDeadlineNS: UInt64 = 0
    private var targetBufferSamples = 14_400
    private var clockCorrectionPPM: Double = 0
    private var lastAdaptationNS: UInt64 = 0, lastUnderrunCount: UInt64 = 0
    private var stableWindows = 0, recentMinimumFIFO = Int.max

    private(set) var preset = VBANPreset(name:"Preset 1",host:"",port:6980,streamName:"MisMeeter")
    private(set) var transmissionMode: VBANTransmissionMode = .automatic

    var onStateChange: ((String)->Void)?
    var onBufferLevel: ((Int)->Void)?
    var onUnderruns: ((UInt64)->Void)?
    var onPacketsSent: ((UInt64)->Void)?
    var onPrimedChange: ((Bool)->Void)?
    var onAdaptiveStats: ((Double,Double)->Void)?

    func configure(preset: VBANPreset, transmissionMode: VBANTransmissionMode) {
        queue.sync {
            self.preset=preset; self.transmissionMode=transmissionMode
            self.targetBufferSamples=transmissionMode.initialTargetSamples
        }
    }

    func start() {
        queue.async {
            self.stopLocked()
            let host=self.preset.host.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !host.isEmpty, let port=NWEndpoint.Port(rawValue:self.preset.port) else {
                self.onStateChange?("Invalid VBAN destination"); return
            }
            let parameters=NWParameters.udp
            parameters.serviceClass = .interactiveVoice
            let c=NWConnection(host:NWEndpoint.Host(host),port:port,using:parameters)
            c.stateUpdateHandler={ [weak self] s in
                guard let self else { return }
                switch s {
                case .ready:self.onStateChange?("Prebuffering audio…")
                case .preparing:self.onStateChange?("Connecting…")
                case .waiting(let e):self.onStateChange?("Waiting: \(e.localizedDescription)")
                case .failed(let e):self.onStateChange?("Network error: \(e.localizedDescription)")
                case .cancelled:self.onStateChange?("Stopped")
                default:break
                }
            }
            self.connection=c; self.frameCounter=0; self.underruns=0; self.packetsSent=0
            self.primed=false; self.clockCorrectionPPM=0
            self.targetBufferSamples=self.transmissionMode.initialTargetSamples
            self.lastAdaptationNS=0; self.lastUnderrunCount=0; self.stableWindows=0
            self.recentMinimumFIFO=Int.max; self.fifo.clear()
            c.start(queue:self.queue); self.publishStats()
        }
    }

    func stop(){ queue.async { self.stopLocked() } }
    func setMuted(_ value:Bool){ queue.async { self.muted=value } }

    func enqueue(_ samples:[Int16]) {
        guard !samples.isEmpty else { return }
        queue.async {
            guard self.connection != nil else { return }
            self.fifo.append(samples)
            self.recentMinimumFIFO=min(self.recentMinimumFIFO,self.fifo.count)
            if !self.primed && self.fifo.count >= self.transmissionMode.startBufferSamples {
                self.primed=true; self.onPrimedChange?(true); self.onStateChange?("VBAN streaming")
                let now=DispatchTime.now().uptimeNanoseconds
                self.nextDeadlineNS=now; self.lastAdaptationNS=now
                self.recentMinimumFIFO=self.fifo.count; self.armNext()
            }
            self.onBufferLevel?(self.fifo.count)
        }
    }

    private func armNext() {
        guard primed else { return }
        timer?.setEventHandler{}; timer?.cancel()
        let now=DispatchTime.now().uptimeNanoseconds
        if nextDeadlineNS < now { nextDeadlineNS=now } // never create a catch-up burst
        let t=DispatchSource.makeTimerSource(queue:queue)
        t.schedule(deadline:DispatchTime(uptimeNanoseconds:nextDeadlineNS),leeway:.microseconds(30))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendOne(); self.updateController()
            self.nextDeadlineNS &+= self.intervalNS(); self.armNext()
        }
        timer=t; t.resume()
    }

    private func intervalNS()->UInt64 {
        let base=VBANPacket.packetDurationSeconds*1_000_000_000.0
        return UInt64(max(1,base*(1-clockCorrectionPPM/1_000_000)))
    }

    private func updateController() {
        let current=fifo.count
        recentMinimumFIFO=min(recentMinimumFIFO,current)
        let target=max(256,targetBufferSamples)
        let error=Double(current-target)/Double(target)
        let maxPPM=transmissionMode.maxClockCorrectionPPM
        let desired=max(-maxPPM,min(maxPPM,error*maxPPM))
        clockCorrectionPPM=clockCorrectionPPM*0.97+desired*0.03

        guard transmissionMode == .automatic else { publishStats(); return }
        let now=DispatchTime.now().uptimeNanoseconds
        guard now &- lastAdaptationNS >= 3_000_000_000 else { publishStats(); return }

        if underruns != lastUnderrunCount || recentMinimumFIFO < 512 {
            targetBufferSamples=min(14_400,targetBufferSamples+2_400) // +50ms quickly
            stableWindows=0
        } else {
            stableWindows += 1
            if stableWindows >= 2 && targetBufferSamples > 2_400 {
                targetBufferSamples=max(2_400,targetBufferSamples-1_200) // -25ms slowly
                stableWindows=0
            }
        }
        lastUnderrunCount=underruns; recentMinimumFIFO=fifo.count; lastAdaptationNS=now
        publishStats()
    }

    private func publishStats() {
        onAdaptiveStats?(Double(targetBufferSamples)/VBANPacket.sampleRate*1000,clockCorrectionPPM)
    }

    private func sendOne() {
        guard let connection else { return }
        let source:[Int16]
        if let b=fifo.pop(VBANPacket.samplesPerPacket) { source=b }
        else {
            source=[Int16](repeating:0,count:VBANPacket.samplesPerPacket)
            underruns &+= 1; onUnderruns?(underruns)
        }
        let outgoing=muted ? [Int16](repeating:0,count:VBANPacket.samplesPerPacket) : source
        let packet=VBANPacket.make(samples:outgoing,streamName:preset.sanitizedStreamName,frameCounter:frameCounter)
        frameCounter &+= 1; packetsSent &+= 1
        connection.send(content:packet,completion:.contentProcessed { [weak self] e in
            if let e { self?.onStateChange?("UDP send error: \(e.localizedDescription)") }
        })
        onPacketsSent?(packetsSent); onBufferLevel?(fifo.count)
    }

    private func stopLocked() {
        timer?.setEventHandler{}; timer?.cancel(); timer=nil
        connection?.stateUpdateHandler=nil; connection?.cancel(); connection=nil
        fifo.clear(); frameCounter=0; packetsSent=0; underruns=0; primed=false
        clockCorrectionPPM=0; nextDeadlineNS=0; onPrimedChange?(false)
    }
}

import AVFoundation
import Foundation

final class FloatRingBuffer {
    private var storage: [Float]; private var read = 0; private var write = 0; private var used = 0
    private let lock = NSLock()
    init(capacity: Int) { storage = .init(repeating:0, count:max(1,capacity)) }
    func push(_ values: [Float]) { lock.lock(); defer { lock.unlock() }; for v in values { if used == storage.count { read = (read+1)%storage.count; used -= 1 }; storage[write]=v; write=(write+1)%storage.count; used += 1 } }
    func pop(_ count: Int) -> [Float] { lock.lock(); defer { lock.unlock() }; let n=min(count,used); var out=[Float](); out.reserveCapacity(count); for _ in 0..<n { out.append(storage[read]); read=(read+1)%storage.count; used -= 1 }; if n<count { out.append(contentsOf: repeatElement(0,count:count-n)) }; return out }
    var count: Int { lock.lock(); defer { lock.unlock() }; return used }
    func reset() { lock.lock(); read=0; write=0; used=0; lock.unlock() }
}

final class AudioEngineService {
    struct Meter { let rms: Float; let peak: Float }
    var onMeter: ((Meter)->Void)?
    var onTransmitPCM: ((Data, Int)->Void)?
    private let engine = AVAudioEngine(); private let player = AVAudioPlayerNode(); private let queue = DispatchQueue(label:"dev.mismeeter.audio", qos:.userInteractive)
    private var timer: DispatchSourceTimer?; private var ring: FloatRingBuffer; private(set) var sampleRate: Double = 48_000; private(set) var channels: Int = 2
    init() { ring = FloatRingBuffer(capacity: 48_000 * 2) }

    func start(sampleRate: Double = 48_000, channels: Int = 2, ioBuffer: TimeInterval = 0.005, capture: Bool) throws {
        stop(); self.sampleRate=sampleRate; self.channels=channels; ring=FloatRingBuffer(capacity:Int(sampleRate)*channels)
        let session=AVAudioSession.sharedInstance(); try session.setCategory(.playAndRecord, mode:.measurement, options:[.allowBluetoothHFP,.allowAirPlay]); try session.setPreferredSampleRate(sampleRate); try session.setPreferredIOBufferDuration(ioBuffer); try session.setActive(true)
        engine.attach(player); guard let format=AVAudioFormat(commonFormat:.pcmFormatFloat32, sampleRate:sampleRate, channels:AVAudioChannelCount(channels), interleaved:false) else { throw VBANError.invalidFormat }
        engine.connect(player,to:engine.mainMixerNode,format:format)
        if capture { let input=engine.inputNode; let inputFormat=input.outputFormat(forBus:0); input.installTap(onBus:0,bufferSize:256,format:inputFormat) { [weak self] buffer,_ in self?.capture(buffer) } }
        engine.prepare(); try engine.start(); player.play(); startPump(format:format)
    }
    func stop() { timer?.cancel(); timer=nil; if engine.isRunning { engine.inputNode.removeTap(onBus:0) }; player.stop(); engine.stop(); engine.reset(); ring.reset() }
    func enqueue(_ samples:[Float]) { ring.push(samples) }
    var estimatedLatencyMS: Double { Double(ring.count / max(channels,1))/sampleRate*1000 + AVAudioSession.sharedInstance().ioBufferDuration*1000 }

    private func startPump(format: AVAudioFormat) {
        let t=DispatchSource.makeTimerSource(queue:queue); t.schedule(deadline:.now(),repeating:.milliseconds(5),leeway:.milliseconds(1)); t.setEventHandler { [weak self] in self?.pump(format:format) }; timer=t; t.resume()
    }
    private func pump(format: AVAudioFormat) {
        let frames=256, total=frames*channels, samples=ring.pop(total); guard let b=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(frames)), let data=b.floatChannelData else { return }; b.frameLength=AVAudioFrameCount(frames)
        var sum:Float=0, peak:Float=0
        for f in 0..<frames { for c in 0..<channels { let v=samples[f*channels+c]; data[c][f]=v; sum += v*v; peak=max(peak,abs(v)) } }
        player.scheduleBuffer(b,completionHandler:nil); let rms=sqrt(sum/Float(max(1,total))); DispatchQueue.main.async { [weak self] in self?.onMeter?(Meter(rms:rms,peak:peak)) }
    }
    private func capture(_ buffer: AVAudioPCMBuffer) {
        guard let src=buffer.floatChannelData else { return }; let frames=Int(buffer.frameLength), sourceChannels=Int(buffer.format.channelCount); var interleaved=[Float](); interleaved.reserveCapacity(frames*channels)
        for f in 0..<frames { for c in 0..<channels { interleaved.append(src[min(c,sourceChannels-1)][f]) } }
        interleaved.withUnsafeBufferPointer { ptr in guard let base=ptr.baseAddress else{return}; onTransmitPCM?(VBANPCM.encodeInt16(base,count:ptr.count),frames) }
    }
}
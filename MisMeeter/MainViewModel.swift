import Foundation
import SwiftUI

@MainActor final class MainViewModel: ObservableObject {
    enum Mode: String, CaseIterable { case receive="Receive", transmit="Transmit" }
    @AppStorage("host") var host="192.168.1.100"; @AppStorage("port") var port=6980; @AppStorage("stream") var streamName="Stream1"; @AppStorage("ioBuffer") var ioBuffer=0.005
    @Published var mode:Mode = .receive; @Published private(set) var running=false; @Published private(set) var status="Disconnected"; @Published private(set) var rms:Float=0; @Published private(set) var peak:Float=0; @Published private(set) var packets:UInt64=0; @Published private(set) var lost:UInt64=0; @Published private(set) var latencyMS:Double=0
    private let socket=VBANSocketManager(); private let audio=AudioEngineService(); private var frame:UInt32=0; private var lastRX:UInt32?; private var statsTimer:Timer?
    init() {
        socket.onState = { [weak self] s in self?.status = { switch s { case .stopped:return "Disconnected"; case .listening:return "Listening"; case .connecting:return "Connecting"; case .ready:return "Active"; case .failed(let e):return "Error: \(e)" } }() }
        socket.onPacket = { [weak self] data in self?.consume(data) }
        audio.onMeter = { [weak self] m in self?.rms=m.rms; self?.peak=m.peak }
    }
    func toggle() { running ? stop() : start() }
    func start() {
        do { try audio.start(sampleRate:48_000,channels:2,ioBuffer:ioBuffer,capture:mode == .transmit); if mode == .receive { try socket.listen(port:UInt16(port)) } else { socket.connect(host:host,port:UInt16(port)); audio.onTransmitPCM = { [weak self] payload,frames in self?.transmit(payload:payload,frames:frames) } }; running=true; status = mode == .receive ? "Listening" : "Connecting"; statsTimer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.latencyMS=self?.audio.estimatedLatencyMS ?? 0 } } catch { status="Error: \(error.localizedDescription)"; stop() }
    }
    func stop() { statsTimer?.invalidate(); statsTimer=nil; socket.stop(); audio.stop(); audio.onTransmitPCM=nil; running=false; status="Disconnected" }
    private nonisolated func consume(_ data:Data) {
        do { let p=try VBANPacket(data:data); guard p.header.protocolType == .audio, p.header.streamName == streamName else{return}; let samples=try VBANPCM.decode(p); audio.enqueue(samples); Task { @MainActor [weak self] in guard let self else{return}; packets += 1; if let last=lastRX { let expected=last &+ 1; let d=p.header.frameCounter &- expected; if p.header.frameCounter != expected && d < 4096 { lost += UInt64(d) } }; lastRX=p.header.frameCounter } } catch { }
    }
    private nonisolated func transmit(payload:Data,frames:Int) { Task { @MainActor [weak self] in guard let self else{return}; do { let h=try VBANHeader(sampleRate:48_000,samplesPerPacket:min(frames,256),channels:2,dataType:.int16,streamName:streamName,frameCounter:frame); frame &+= 1; socket.send(try VBANPacket(data:h.encoded()+payload).encoded()) } catch {} } }
}
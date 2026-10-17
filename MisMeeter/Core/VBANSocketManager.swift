import Foundation
import Network

final class VBANSocketManager {
    enum State: Equatable { case stopped, listening, connecting, ready, failed(String) }
    var onPacket: ((Data) -> Void)?
    var onState: ((State) -> Void)?
    private let queue = DispatchQueue(label: "dev.mismeeter.network", qos: .userInteractive)
    private let monitor = NWPathMonitor()
    private var listener: NWListener?
    private var peers: [ObjectIdentifier:NWConnection] = [:]
    private var sender: NWConnection?
    private var destination: (String, UInt16)?
    private var listenPort: UInt16?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in guard path.status == .satisfied else { return }; self?.queue.async { self?.reconnect() } }
        monitor.start(queue: queue)
    }
    deinit { monitor.cancel(); listener?.cancel(); sender?.cancel() }

    func listen(port: UInt16) throws {
        listenPort = port; listener?.cancel()
        let params = NWParameters.udp; params.allowLocalEndpointReuse = true
        guard let p = NWEndpoint.Port(rawValue: port) else { throw VBANError.invalidFormat }
        let l = try NWListener(using: params, on: p); listener = l
        l.stateUpdateHandler = { [weak self] s in
            switch s { case .ready: self?.publish(.listening); case .failed(let e): self?.publish(.failed(e.localizedDescription)); self?.retryListener(); default: break }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
    }

    func connect(host: String, port: UInt16) { queue.async { self.destination = (host,port); self.makeSender(host: host, port: port) } }
    func send(_ data: Data) { queue.async { self.sender?.send(content: data, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in }) } }
    func stop() { queue.async { self.listener?.cancel(); self.listener = nil; self.sender?.cancel(); self.sender = nil; self.peers.values.forEach { $0.cancel() }; self.peers.removeAll(); self.publish(.stopped) } }

    private func accept(_ c: NWConnection) {
        let id = ObjectIdentifier(c); peers[id] = c
        c.stateUpdateHandler = { [weak self, weak c] s in guard let self, let c else { return }; if case .ready = s { self.receive(c) }; if case .failed = s { self.peers.removeValue(forKey:id) }; if case .cancelled = s { self.peers.removeValue(forKey:id) } }
        c.start(queue: queue)
    }
    private func receive(_ c: NWConnection) { c.receiveMessage { [weak self, weak c] data,_,_,error in guard let self, let c else { return }; if let data, !data.isEmpty { self.onPacket?(data) }; if error == nil { self.receive(c) } } }
    private func makeSender(host: String, port: UInt16) {
        sender?.cancel(); guard let p = NWEndpoint.Port(rawValue: port) else { return }; publish(.connecting)
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: .udp); sender = c
        c.stateUpdateHandler = { [weak self] s in switch s { case .ready: self?.publish(.ready); case .failed(let e): self?.publish(.failed(e.localizedDescription)); self?.queue.asyncAfter(deadline:.now()+1) { self?.reconnect() }; default: break } }
        c.start(queue: queue)
    }
    private func reconnect() { if let d = destination { makeSender(host:d.0, port:d.1) } }
    private func retryListener() { guard let p = listenPort else { return }; queue.asyncAfter(deadline:.now()+1) { try? self.listen(port:p) } }
    private func publish(_ state: State) { DispatchQueue.main.async { [weak self] in self?.onState?(state) } }
}
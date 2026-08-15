import Foundation
import Network

final class VBANTransmitter {
    private let queue = DispatchQueue(label: "dev.mismeeter.vban.tx", qos: .userInteractive)
    private var connection: NWConnection?
    private var pendingSamples: [Int16] = []
    private var frameCounter: UInt32 = 0

    private(set) var host = ""
    private(set) var port: UInt16 = 6980
    private(set) var streamName = "MisMeeter"

    var onStateChange: ((String) -> Void)?

    func configure(host: String, port: UInt16, streamName: String) {
        queue.sync {
            self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            self.port = port
            self.streamName = Self.sanitize(streamName)
        }
    }

    func start() {
        queue.async {
            self.stopLocked()

            guard !self.host.isEmpty,
                  let nwPort = NWEndpoint.Port(rawValue: self.port) else {
                self.onStateChange?("Invalid destination")
                return
            }

            let c = NWConnection(
                host: NWEndpoint.Host(self.host),
                port: nwPort,
                using: .udp
            )

            c.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.onStateChange?("VBAN ready")
                case .preparing: self?.onStateChange?("Connecting…")
                case .waiting(let e): self?.onStateChange?("Waiting: \(e.localizedDescription)")
                case .failed(let e): self?.onStateChange?("Network error: \(e.localizedDescription)")
                case .cancelled: self?.onStateChange?("Stopped")
                default: break
                }
            }

            self.connection = c
            self.pendingSamples.removeAll(keepingCapacity: true)
            self.frameCounter = 0
            c.start(queue: self.queue)
        }
    }

    func stop() {
        queue.async { self.stopLocked() }
    }

    func enqueue(_ samples: [Int16], muted: Bool) {
        guard !samples.isEmpty else { return }

        queue.async {
            guard self.connection != nil else { return }

            if muted {
                self.pendingSamples.append(contentsOf: repeatElement(0, count: samples.count))
            } else {
                self.pendingSamples.append(contentsOf: samples)
            }

            while self.pendingSamples.count >= VBANPacket.samplesPerPacket {
                let chunk = self.pendingSamples.prefix(VBANPacket.samplesPerPacket)
                let packet = VBANPacket.make(
                    samples: chunk,
                    streamName: self.streamName,
                    frameCounter: self.frameCounter
                )

                self.frameCounter &+= 1
                self.pendingSamples.removeFirst(VBANPacket.samplesPerPacket)

                self.connection?.send(
                    content: packet,
                    completion: .contentProcessed { [weak self] error in
                        if let error {
                            self?.onStateChange?("UDP send error: \(error.localizedDescription)")
                        }
                    }
                )
            }
        }
    }

    private func stopLocked() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        pendingSamples.removeAll(keepingCapacity: false)
        frameCounter = 0
    }

    private static func sanitize(_ value: String) -> String {
        let ascii = value.unicodeScalars.filter { $0.isASCII }
        let name = String(String.UnicodeScalarView(ascii)).prefix(16)
        return name.isEmpty ? "MisMeeter" : String(name)
    }
}

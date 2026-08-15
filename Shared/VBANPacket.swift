import Foundation

enum VBANPacket {
    static let sampleRate: Double = 48_000
    static let sampleRateIndex: UInt8 = 3
    static let channelCount = 1
    static let samplesPerPacket = 256
    static let packetDurationSeconds = Double(samplesPerPacket) / sampleRate

    static func make(
        samples: [Int16],
        streamName: String,
        frameCounter: UInt32
    ) -> Data {
        precondition(samples.count == samplesPerPacket)

        var packet = Data(capacity: 28 + samples.count * 2)

        // VBAN
        packet.append(contentsOf: [0x56, 0x42, 0x41, 0x4E])

        // AUDIO protocol + 48 kHz sample-rate index.
        packet.append(sampleRateIndex)

        // VBAN stores nbs and nbc as N - 1.
        packet.append(UInt8(samples.count - 1))
        packet.append(UInt8(channelCount - 1))

        // Native PCM, signed Int16.
        packet.append(0x01)

        var name = Array(streamName.utf8.prefix(16))
        if name.count < 16 {
            name.append(contentsOf: repeatElement(0, count: 16 - name.count))
        }
        packet.append(contentsOf: name)

        var frame = frameCounter.littleEndian
        withUnsafeBytes(of: &frame) { packet.append(contentsOf: $0) }

        for value in samples {
            var sample = value.littleEndian
            withUnsafeBytes(of: &sample) { packet.append(contentsOf: $0) }
        }

        return packet
    }
}

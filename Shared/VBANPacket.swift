import Foundation

enum VBANPacket {
    static let sampleRate: Double = 48_000
    static let sampleRateIndex: UInt8 = 3
    static let channelCount = 1
    static let samplesPerPacket = 256

    static func make(
        samples: ArraySlice<Int16>,
        streamName: String,
        frameCounter: UInt32
    ) -> Data {
        precondition(!samples.isEmpty && samples.count <= 256)

        var packet = Data(capacity: 28 + samples.count * 2)

        packet.append(contentsOf: [0x56, 0x42, 0x41, 0x4E]) // "VBAN"
        packet.append(sampleRateIndex)                       // AUDIO subprotocol
        packet.append(UInt8(samples.count - 1))
        packet.append(UInt8(channelCount - 1))
        packet.append(0x01)                                 // Int16 + native PCM

        var streamBytes = Array(streamName.utf8.prefix(16))
        if streamBytes.count < 16 {
            streamBytes.append(contentsOf: repeatElement(0, count: 16 - streamBytes.count))
        }
        packet.append(contentsOf: streamBytes)

        var littleFrame = frameCounter.littleEndian
        withUnsafeBytes(of: &littleFrame) { packet.append(contentsOf: $0) }

        for sample in samples {
            var littleSample = sample.littleEndian
            withUnsafeBytes(of: &littleSample) { packet.append(contentsOf: $0) }
        }

        return packet
    }
}

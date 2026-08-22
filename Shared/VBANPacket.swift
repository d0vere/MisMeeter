enum VBANPacket {
    static let sampleRate: Double = 48_000
    static let sampleRateIndex: UInt8 = 3
    static let samplesPerPacket = 256
    static let packetDurationSeconds = Double(samplesPerPacket) / sampleRate
}

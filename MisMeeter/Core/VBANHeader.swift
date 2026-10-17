import Foundation

enum VBANProtocol: UInt8, Sendable { case audio = 0x00, serial = 0x20, text = 0x40, service = 0x60, user = 0xE0 }
enum VBANDataType: UInt8, CaseIterable, Sendable { case uint8 = 0, int16 = 1, int24 = 2, int32 = 3, float32 = 4, float64 = 5, int12 = 6, int10 = 7
    var bytesPerSample: Int? { switch self { case .uint8: return 1; case .int16: return 2; case .int24: return 3; case .int32, .float32: return 4; case .float64: return 8; case .int12, .int10: return nil } }
}
enum VBANError: Error { case shortPacket, invalidMagic, invalidFormat, unsupportedCodec, invalidPayload }

struct VBANHeader: Sendable, Equatable {
    static let size = 28
    static let sampleRates = [6000,12000,24000,48000,96000,192000,384000,8000,16000,32000,64000,128000,256000,512000,11025,22050,44100,88200,176400,352800,705600]
    var protocolType: VBANProtocol
    var sampleRate: Int
    var samplesPerPacket: Int
    var channels: Int
    var dataType: VBANDataType
    var streamName: String
    var frameCounter: UInt32

    init(protocolType: VBANProtocol = .audio, sampleRate: Int, samplesPerPacket: Int, channels: Int, dataType: VBANDataType, streamName: String, frameCounter: UInt32) throws {
        guard Self.sampleRates.contains(sampleRate), (1...256).contains(samplesPerPacket), (1...256).contains(channels), streamName.utf8.count <= 16, streamName.utf8.allSatisfy({ $0 < 128 }) else { throw VBANError.invalidFormat }
        self.protocolType = protocolType; self.sampleRate = sampleRate; self.samplesPerPacket = samplesPerPacket; self.channels = channels; self.dataType = dataType; self.streamName = streamName; self.frameCounter = frameCounter
    }

    init(data: Data) throws {
        guard data.count >= Self.size else { throw VBANError.shortPacket }
        let b = [UInt8](data.prefix(Self.size))
        guard Array(b[0..<4]) == [0x56,0x42,0x41,0x4E] else { throw VBANError.invalidMagic }
        guard let proto = VBANProtocol(rawValue: b[4] & 0xE0), Int(b[4] & 0x1F) < Self.sampleRates.count, let type = VBANDataType(rawValue: b[7] & 0x07), (b[7] & 0xF0) == 0 else { throw VBANError.invalidFormat }
        protocolType = proto; sampleRate = Self.sampleRates[Int(b[4] & 0x1F)]; samplesPerPacket = Int(b[5]) + 1; channels = Int(b[6]) + 1; dataType = type
        streamName = String(bytes: b[8..<24].prefix { $0 != 0 }, encoding: .ascii) ?? ""
        frameCounter = UInt32(b[24]) | UInt32(b[25]) << 8 | UInt32(b[26]) << 16 | UInt32(b[27]) << 24
    }

    func encoded() throws -> Data {
        guard let sr = Self.sampleRates.firstIndex(of: sampleRate) else { throw VBANError.invalidFormat }
        var b = [UInt8](repeating: 0, count: Self.size); b[0...3] = [0x56,0x42,0x41,0x4E]; b[4] = protocolType.rawValue | UInt8(sr); b[5] = UInt8(samplesPerPacket - 1); b[6] = UInt8(channels - 1); b[7] = dataType.rawValue
        for (i,v) in streamName.utf8.prefix(16).enumerated() { b[8+i] = v }
        b[24] = UInt8(truncatingIfNeeded: frameCounter); b[25] = UInt8(truncatingIfNeeded: frameCounter >> 8); b[26] = UInt8(truncatingIfNeeded: frameCounter >> 16); b[27] = UInt8(truncatingIfNeeded: frameCounter >> 24)
        return Data(b)
    }
}

struct VBANPacket: Sendable {
    let header: VBANHeader; let payload: Data
    init(data: Data) throws {
        header = try VBANHeader(data: data); payload = Data(data.dropFirst(VBANHeader.size))
        if header.protocolType == .audio, let bytes = header.dataType.bytesPerSample {
            guard payload.count == header.samplesPerPacket * header.channels * bytes else { throw VBANError.invalidPayload }
        }
    }
    func encoded() throws -> Data { try header.encoded() + payload }
}

enum VBANPCM {
    static func decode(_ packet: VBANPacket) throws -> [Float] {
        let p = [UInt8](packet.payload)
        switch packet.header.dataType {
        case .uint8: return p.map { (Float($0) - 128) / 128 }
        case .int16: return stride(from: 0, to: p.count, by: 2).map { Float(Int16(bitPattern: UInt16(p[$0]) | UInt16(p[$0+1]) << 8)) / 32768 }
        case .int24: return stride(from: 0, to: p.count, by: 3).map { i in var v = Int32(p[i]) | Int32(p[i+1]) << 8 | Int32(p[i+2]) << 16; if v & 0x800000 != 0 { v |= ~0xFFFFFF }; return Float(v) / 8_388_608 }
        case .int32: return stride(from: 0, to: p.count, by: 4).map { i in let v = UInt32(p[i]) | UInt32(p[i+1]) << 8 | UInt32(p[i+2]) << 16 | UInt32(p[i+3]) << 24; return Float(Int32(bitPattern: v)) / 2_147_483_648 }
        case .float32: return stride(from: 0, to: p.count, by: 4).map { i in Float(bitPattern: UInt32(p[i]) | UInt32(p[i+1]) << 8 | UInt32(p[i+2]) << 16 | UInt32(p[i+3]) << 24) }
        default: throw VBANError.invalidFormat
        }
    }
    static func encodeInt16(_ samples: UnsafePointer<Float>, count: Int) -> Data {
        var out = Data(capacity: count * 2)
        for i in 0..<count { let x = max(-1, min(0.9999695, samples[i])); var v = Int16(x * 32768).littleEndian; withUnsafeBytes(of: &v) { out.append(contentsOf: $0) } }
        return out
    }
}
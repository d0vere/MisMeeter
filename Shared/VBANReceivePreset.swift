struct VBANReceivePreset: Equatable {
    var name: String
    var port: UInt16
    var streamName: String

    var sanitizedStreamName: String {
        let scalars = streamName.unicodeScalars.filter {
            $0.isASCII && (32...126).contains(Int($0.value))
        }
        let value = String(String.UnicodeScalarView(scalars)).prefix(16)
        return value.isEmpty ? "MisMeeterRX" : String(value)
    }
}

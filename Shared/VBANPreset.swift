import Foundation

struct VBANPreset: Equatable {
    var name: String
    var host: String
    var port: UInt16
    var streamName: String

    var destinationLabel: String {
        "\(host):\(port)"
    }

    var sanitizedStreamName: String {
        let scalars = streamName.unicodeScalars.filter { $0.isASCII }
        let value = String(String.UnicodeScalarView(scalars)).prefix(16)
        return value.isEmpty ? "MisMeeter" : String(value)
    }
}

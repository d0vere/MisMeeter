import ActivityKit
import Foundation

struct MicActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isMuted: Bool
        var isStreaming: Bool
        var isReceiving: Bool
        var isReceiveMuted: Bool
        var destinationLabel: String
        var presetLabel: String
        var startedAt: Date?
        var statusLabel: String

        init(snapshot: SharedTransportSnapshot) {
            isMuted = snapshot.isMuted
            isStreaming = snapshot.isStreaming
            isReceiving = snapshot.isReceiving
            isReceiveMuted = snapshot.isReceiveMuted
            destinationLabel = snapshot.destination
            presetLabel = snapshot.presetName
            startedAt = snapshot.startedAt
            statusLabel = snapshot.status
        }
    }

    var sessionName: String
}

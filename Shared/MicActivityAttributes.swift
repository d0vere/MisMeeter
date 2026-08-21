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
        var sendPresetLabel: String
        var receivePresetLabel: String
        var startedAt: Date?
        var statusLabel: String
        var presentationRevision: UInt64?

        init(snapshot: SharedTransportSnapshot, presentationRevision: UInt64 = 0) {
            isMuted = snapshot.isMuted
            isStreaming = snapshot.isStreaming
            isReceiving = snapshot.isReceiving
            isReceiveMuted = snapshot.isReceiveMuted
            destinationLabel = snapshot.destination
            presetLabel = snapshot.presetName
            sendPresetLabel = snapshot.sendPresetName
            receivePresetLabel = snapshot.receivePresetName
            startedAt = snapshot.startedAt
            statusLabel = snapshot.status
            self.presentationRevision = presentationRevision
        }
    }

    var sessionName: String
}

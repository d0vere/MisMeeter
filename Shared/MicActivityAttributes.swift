import ActivityKit
import Foundation

struct MicActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isMuted: Bool
        var isStreaming: Bool
        var isReceiving: Bool
        var destinationLabel: String
        var presetLabel: String
        var startedAt: Date?
        var statusLabel: String
    }

    var sessionName: String
}

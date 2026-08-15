import ActivityKit
import Foundation

struct MicActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isMuted: Bool
        var connectionLabel: String
    }

    var sessionName: String
}

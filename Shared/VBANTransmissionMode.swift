import Foundation

enum VBANTransmissionMode: Int, CaseIterable, Identifiable {
    case lowLatency = 0
    case balanced = 1
    case maximumStability = 2
    case automatic = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .lowLatency: return "Low"
        case .balanced: return "Balanced"
        case .maximumStability: return "Maximum"
        case .automatic: return "Auto"
        }
    }

    var detail: String {
        switch self {
        case .lowLatency:
            return "Manual target ≈75 ms"
        case .balanced:
            return "Manual target ≈150 ms"
        case .maximumStability:
            return "Manual target ≈250 ms"
        case .automatic:
            return "PLL-locked automatic latency"
        }
    }

    var startBufferSamples: Int {
        switch self {
        case .lowLatency: return 4_800       // one observed 100 ms callback
        case .balanced: return 7_200         // 150 ms
        case .maximumStability: return 12_000 // 250 ms
        case .automatic: return 9_600        // 200 ms startup
        }
    }

    var initialTargetSamples: Int {
        switch self {
        case .lowLatency: return 3_600
        case .balanced: return 7_200
        case .maximumStability: return 12_000
        case .automatic: return 7_200
        }
    }

    var minimumTargetSamples: Int {
        switch self {
        case .lowLatency: return 2_400       // 50 ms
        case .balanced: return 4_800         // 100 ms
        case .maximumStability: return 7_200 // 150 ms
        case .automatic: return 2_400        // 50 ms floor
        }
    }

    /// Maximum number of consecutive packets allowed when the scheduler wakes late.
    /// VBAN receivers are designed to tolerate small packet bursts.
    var maxCatchUpBurst: Int {
        switch self {
        case .lowLatency: return 4
        case .balanced: return 5
        case .maximumStability: return 6
        case .automatic: return 5
        }
    }
}

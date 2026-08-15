import Foundation

enum VBANTransmissionMode: Int, CaseIterable, Identifiable {
    case lowLatency = 0, balanced = 1, maximumStability = 2, automatic = 3
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
        case .lowLatency: return "Manual target ≈100 ms"
        case .balanced: return "Manual target ≈200 ms"
        case .maximumStability: return "Manual target ≈300 ms"
        case .automatic: return "Starts safe, then searches for the lowest stable buffer"
        }
    }
    var startBufferSamples: Int {
        switch self {
        case .lowLatency: return 4_800
        case .balanced: return 9_600
        case .maximumStability, .automatic: return 14_400
        }
    }
    var initialTargetSamples: Int { startBufferSamples }
    var maxClockCorrectionPPM: Double {
        switch self {
        case .lowLatency: return 1_500
        case .balanced: return 2_000
        case .maximumStability: return 2_500
        case .automatic: return 3_000
        }
    }
}

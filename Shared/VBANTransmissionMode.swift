import Foundation

enum VBANTransmissionMode: Int, CaseIterable, Identifiable {
    case lowLatency = 0
    case balanced = 1
    case maximumStability = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .lowLatency:
            return "Low Latency"
        case .balanced:
            return "Balanced"
        case .maximumStability:
            return "Maximum"
        }
    }

    var detail: String {
        switch self {
        case .lowLatency:
            return "≈100 ms startup buffer"
        case .balanced:
            return "≈200 ms startup buffer"
        case .maximumStability:
            return "≈300 ms startup buffer"
        }
    }

    /// Observed iOS input callbacks on the test device are 4800 samples (100 ms).
    /// Buffering whole callback-sized chunks prevents the paced sender from
    /// starving between those callbacks.
    var startBufferSamples: Int {
        switch self {
        case .lowLatency:
            return 4_800
        case .balanced:
            return 9_600
        case .maximumStability:
            return 14_400
        }
    }

    /// Once playback begins, this is the desired FIFO center point.
    var targetBufferSamples: Int {
        switch self {
        case .lowLatency:
            return 2_400
        case .balanced:
            return 4_800
        case .maximumStability:
            return 9_600
        }
    }

    /// Very small clock correction to prevent long-term drift.
    /// This does not materially alter pitch; it only nudges packet cadence.
    var maxClockCorrection: Double {
        switch self {
        case .lowLatency:
            return 0.0010      // ±0.10 %
        case .balanced:
            return 0.0015      // ±0.15 %
        case .maximumStability:
            return 0.0020      // ±0.20 %
        }
    }
}

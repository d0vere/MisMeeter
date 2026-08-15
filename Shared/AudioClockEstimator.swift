import Foundation

final class AudioClockEstimator {
    private var windowStartNS: UInt64?
    private var samplesInWindow: UInt64 = 0
    private var emaRate: Double = 48_000

    private let minimumWindowNS: UInt64 = 2_000_000_000
    private let alpha: Double = 0.18

    var measuredRate: Double {
        emaRate
    }

    func reset() {
        windowStartNS = nil
        samplesInWindow = 0
        emaRate = 48_000
    }

    /// Call once per captured audio callback.
    /// Returns a new smoothed measured rate occasionally.
    @discardableResult
    func addCapturedSamples(
        _ count: Int,
        nowNS: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Double? {
        guard count > 0 else { return nil }

        if windowStartNS == nil {
            windowStartNS = nowNS
            samplesInWindow = UInt64(count)
            return nil
        }

        samplesInWindow += UInt64(count)

        guard let start = windowStartNS else { return nil }
        let elapsed = nowNS &- start

        guard elapsed >= minimumWindowNS else { return nil }

        let seconds = Double(elapsed) / 1_000_000_000.0
        let instantaneous = Double(samplesInWindow) / seconds

        // Ignore implausible scheduler artifacts during startup/suspension.
        if instantaneous > 44_000 && instantaneous < 52_000 {
            emaRate = emaRate * (1.0 - alpha) + instantaneous * alpha
        }

        windowStartNS = nowNS
        samplesInWindow = 0
        return emaRate
    }
}

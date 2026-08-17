import Darwin
import Foundation

final class MonotonicPacer {
    private var timebase =
        mach_timebase_info_data_t()

    init() {
        mach_timebase_info(
            &timebase
        )
    }

    func nowTicks() -> UInt64 {
        mach_absolute_time()
    }

    func ticks(
        forNanoseconds ns: UInt64
    ) -> UInt64 {
        let numer =
            UInt64(
                timebase.numer
            )

        let denom =
            UInt64(
                timebase.denom
            )

        // ns = ticks * numer / denom
        // ticks = ns * denom / numer
        return ns * denom / numer
    }

    func nanoseconds(
        forTicks ticks: UInt64
    ) -> UInt64 {
        let numer =
            UInt64(
                timebase.numer
            )

        let denom =
            UInt64(
                timebase.denom
            )

        return ticks * numer / denom
    }

    /// Wait until an absolute mach time.
    /// mach_wait_until does not accumulate relative timer drift.
    func wait(
        until deadlineTicks: UInt64
    ) {
        _ = mach_wait_until(
            deadlineTicks
        )
    }
}

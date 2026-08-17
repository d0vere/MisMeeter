import Foundation
import os

final class CaptureRingBuffer {
    struct Snapshot {
        let bufferedFrames: Int
        let overruns: UInt64
    }

    private struct State {
        var readIndex = 0
        var writeIndex = 0
        var count = 0
        var overruns: UInt64 = 0
    }

    private let capacity: Int
    private let storage: UnsafeMutablePointer<Int16>
    private let lock = OSAllocatedUnfairLock(
        initialState: State()
    )

    init(capacityFrames: Int = 48_000) {
        capacity = capacityFrames
        storage = .allocate(
            capacity: capacityFrames
        )
        storage.initialize(
            repeating: 0,
            count: capacityFrames
        )
    }

    deinit {
        storage.deallocate()
    }

    func reset() {
        lock.withLock { state in
            state.readIndex = 0
            state.writeIndex = 0
            state.count = 0
            state.overruns = 0
        }
    }

    /// Realtime-safe in the sense that it performs no heap allocation.
    /// If full, newest audio is dropped and an overrun is counted.
    func write(
        from source: UnsafePointer<Int16>,
        count: Int
    ) {
        guard count > 0 else { return }

        lock.withLock { state in
            for i in 0..<count {
                if state.count >= capacity {
                    state.overruns &+= 1
                    break
                }

                storage[state.writeIndex] =
                    source[i]

                state.writeIndex =
                    (state.writeIndex + 1) %
                    capacity

                state.count += 1
            }
        }
    }

    /// Pull up to maxCount frames into a caller-owned preallocated buffer.
    func read(
        into destination: UnsafeMutablePointer<Int16>,
        maxCount: Int
    ) -> Int {
        guard maxCount > 0 else { return 0 }

        return lock.withLock { state in
            let n = min(
                maxCount,
                state.count
            )

            for i in 0..<n {
                destination[i] =
                    storage[state.readIndex]

                state.readIndex =
                    (state.readIndex + 1) %
                    capacity

                state.count -= 1
            }

            return n
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock { state in
            Snapshot(
                bufferedFrames: state.count,
                overruns: state.overruns
            )
        }
    }
}

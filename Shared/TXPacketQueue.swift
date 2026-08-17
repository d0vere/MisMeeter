import Foundation
import os

final class TXPacketQueue {
    struct Snapshot {
        let bufferedFrames: Int
        let overruns: UInt64
        let targetFrames: Int
    }

    private struct State {
        var readIndex = 0
        var writeIndex = 0
        var count = 0
        var overruns: UInt64 = 0
        var targetFrames = 1024
    }

    private let capacity: Int
    private let storage: UnsafeMutablePointer<Int16>
    private let lock = OSAllocatedUnfairLock(
        initialState: State()
    )

    init(capacityFrames: Int = 48_000) {
        capacity = capacityFrames
        storage = .allocate(capacity: capacityFrames)
        storage.initialize(repeating: 0, count: capacityFrames)
    }

    deinit {
        storage.deallocate()
    }

    func reset(targetFrames: Int = 1024) {
        lock.withLock { state in
            state.readIndex = 0
            state.writeIndex = 0
            state.count = 0
            state.overruns = 0
            state.targetFrames = max(256, min(capacity / 2, targetFrames))
        }
    }

    func setTargetFrames(_ frames: Int) {
        lock.withLock { state in
            state.targetFrames = max(256, min(capacity / 2, frames))
        }
    }

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

                storage[state.writeIndex] = source[i]
                state.writeIndex = (state.writeIndex + 1) % capacity
                state.count += 1
            }
        }
    }

    func readPacket(
        into destination: UnsafeMutablePointer<Int16>
    ) -> Bool {
        lock.withLock { state in
            guard state.count >= VBANPacket.samplesPerPacket else {
                return false
            }

            for i in 0..<VBANPacket.samplesPerPacket {
                destination[i] = storage[state.readIndex]
                state.readIndex = (state.readIndex + 1) % capacity
                state.count -= 1
            }

            return true
        }
    }

    func bufferedFrames() -> Int {
        lock.withLock { $0.count }
    }

    func targetFrames() -> Int {
        lock.withLock { $0.targetFrames }
    }


    /// Drop oldest complete VBAN packets until no more than maxFrames remain.
    /// Returns the number of frames discarded.
    @discardableResult
    func trimToNewest(
        maxFrames: Int
    ) -> Int {
        lock.withLock { state in
            let wanted =
                max(
                    VBANPacket.samplesPerPacket,
                    min(capacity, maxFrames)
                )

            guard state.count > wanted else {
                return 0
            }

            let excess =
                state.count - wanted

            let alignedDrop =
                excess -
                (
                    excess %
                    VBANPacket.samplesPerPacket
                )

            guard alignedDrop > 0 else {
                return 0
            }

            state.readIndex =
                (
                    state.readIndex +
                    alignedDrop
                ) %
                capacity

            state.count -= alignedDrop

            return alignedDrop
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock { state in
            Snapshot(
                bufferedFrames: state.count,
                overruns: state.overruns,
                targetFrames: state.targetFrames
            )
        }
    }
}

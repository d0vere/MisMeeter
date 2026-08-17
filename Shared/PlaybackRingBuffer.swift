import Foundation
import os

final class PlaybackRingBuffer {
    struct Stats {
        let bufferedFrames: Int
        let underflows: UInt64
        let primed: Bool
    }

    private struct State {
        var readFrame = 0
        var writeFrame = 0
        var countFrames = 0
        var targetFrames = 4_800
        var primed = false
        var underflows: UInt64 = 0
    }

    private let capacityFrames: Int
    private let storage: UnsafeMutablePointer<Float>
    private let lock = OSAllocatedUnfairLock(
        initialState: State()
    )

    init(capacityFrames: Int = 96_000) {
        self.capacityFrames = capacityFrames
        storage = .allocate(
            capacity: capacityFrames * 2
        )
        storage.initialize(
            repeating: 0,
            count: capacityFrames * 2
        )
    }

    deinit {
        storage.deallocate()
    }

    func reset(targetFrames: Int) {
        lock.withLock { state in
            state.readFrame = 0
            state.writeFrame = 0
            state.countFrames = 0
            state.targetFrames = max(256, min(capacityFrames / 2, targetFrames))
            state.primed = false
            state.underflows = 0
        }
    }

    /// Push interleaved stereo Float32 frames.
    func pushStereo(
        left: [Float],
        right: [Float]
    ) {
        let frames = min(left.count, right.count)
        guard frames > 0 else { return }

        lock.withLock { state in
            for index in 0..<frames {
                // If full, discard the oldest frame. A fresh live stream is
                // preferable to accumulating seconds of stale audio.
                if state.countFrames >= capacityFrames {
                    state.readFrame =
                        (state.readFrame + 1) % capacityFrames
                    state.countFrames -= 1
                }

                let base = state.writeFrame * 2
                storage[base] = left[index]
                storage[base + 1] = right[index]

                state.writeFrame =
                    (state.writeFrame + 1) % capacityFrames
                state.countFrames += 1
            }

            if !state.primed &&
                state.countFrames >= state.targetFrames {
                state.primed = true
            }
        }
    }

    /// Realtime audio-thread read. No allocation.
    func render(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        lock.withLock { state in
            if !state.primed {
                for i in 0..<frameCount {
                    left[i] = 0
                    right[i] = 0
                }

                if state.countFrames >= state.targetFrames {
                    state.primed = true
                }

                return
            }

            var rendered = 0

            while rendered < frameCount &&
                    state.countFrames > 0 {
                let base = state.readFrame * 2
                left[rendered] = storage[base]
                right[rendered] = storage[base + 1]

                state.readFrame =
                    (state.readFrame + 1) % capacityFrames
                state.countFrames -= 1
                rendered += 1
            }

            if rendered < frameCount {
                for i in rendered..<frameCount {
                    left[i] = 0
                    right[i] = 0
                }

                state.underflows &+= 1
                state.primed = false
            }
        }
    }

    func stats() -> Stats {
        lock.withLock { state in
            Stats(
                bufferedFrames: state.countFrames,
                underflows: state.underflows,
                primed: state.primed
            )
        }
    }
}

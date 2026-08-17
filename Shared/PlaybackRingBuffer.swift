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
    private let scratchLeft: UnsafeMutablePointer<Float>
    private let scratchRight: UnsafeMutablePointer<Float>
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

        scratchLeft = .allocate(
            capacity: 4096
        )
        scratchRight = .allocate(
            capacity: 4096
        )
        scratchLeft.initialize(
            repeating: 0,
            count: 4096
        )
        scratchRight.initialize(
            repeating: 0,
            count: 4096
        )
    }

    deinit {
        storage.deallocate()
        scratchLeft.deallocate()
        scratchRight.deallocate()
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

    /// Realtime audio-thread read. No heap allocation.
    /// The lock closure touches only object-owned storage. The caller's
    /// UnsafeMutablePointers are written after the @Sendable lock closure,
    /// avoiding Swift 6 Sendable diagnostics.
    func render(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        let frames = min(frameCount, 4096)

        lock.withLock { state in
            if !state.primed {
                for i in 0..<frames {
                    scratchLeft[i] = 0
                    scratchRight[i] = 0
                }

                if state.countFrames >= state.targetFrames {
                    state.primed = true
                }

                return
            }

            var rendered = 0

            while rendered < frames &&
                    state.countFrames > 0 {
                let base = state.readFrame * 2

                scratchLeft[rendered] =
                    storage[base]

                scratchRight[rendered] =
                    storage[base + 1]

                state.readFrame =
                    (state.readFrame + 1) % capacityFrames

                state.countFrames -= 1
                rendered += 1
            }

            if rendered < frames {
                for i in rendered..<frames {
                    scratchLeft[i] = 0
                    scratchRight[i] = 0
                }

                state.underflows &+= 1
                state.primed = false
            }
        }

        for i in 0..<frames {
            left[i] = scratchLeft[i]
            right[i] = scratchRight[i]
        }

        if frameCount > frames {
            for i in frames..<frameCount {
                left[i] = 0
                right[i] = 0
            }
        }
    }


    func setTargetFrames(
        _ frames: Int,
        forceReprimeIfBelowTarget: Bool = true
    ) {
        lock.withLock { state in
            let newTarget = max(
                256,
                min(capacityFrames / 2, frames)
            )

            state.targetFrames = newTarget

            // Important: if the safety target is raised while the current
            // queue is below it, stop consuming and genuinely rebuild the
            // requested jitter margin. v1.4 could leave `primed = true`
            // with e.g. 125 ms buffered against a 300 ms target.
            if forceReprimeIfBelowTarget &&
                state.countFrames < newTarget {
                state.primed = false
            } else if state.countFrames >= newTarget {
                state.primed = true
            }
        }
    }

    func targetFrames() -> Int {
        lock.withLock { state in
            state.targetFrames
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

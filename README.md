# MisMeeter v0.7 Adaptive

Auto starts at ~300 ms and reduces its target by 25 ms after stable observation windows, down to 50 ms.
If an underrun/starvation is detected it restores 50 ms of safety immediately.

The sender uses monotonic packet deadlines, avoids catch-up bursts, and applies a small FIFO-based
clock correction reported in ppm.

Modes: Low ~100 ms, Balanced ~200 ms, Maximum ~300 ms, Auto adaptive.

Existing 3 presets, gain slider, background audio, Live Activity and direct VBAN remain.

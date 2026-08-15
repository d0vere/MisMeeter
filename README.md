# MisMeeter v0.8 — PLL / Clock Locked VBAN

v0.8 addresses the key result observed in v0.7:

- sender buffer could remain around 300+ ms
- adaptive target was much lower
- old clock correction hit its maximum
- underruns remained zero

That indicates the sender scheduler was losing average throughput and silently accumulating latency.

## v0.8 changes

### 1. Measured capture clock
MisMeeter now estimates the real captured sample rate from:
- number of samples received
- monotonic elapsed time

The measured rate is smoothed over multi-second windows.

### 2. PLL-locked TX rate
VBAN packet cadence follows the measured capture rate rather than assuming that a software timer
will execute at exactly 48,000 samples/s.

FIFO occupancy adds only a smooth rate trim.

### 3. No more "reset deadline to now"
If iOS wakes the sender late, v0.8 preserves the original packet-clock phase.

The old approach could permanently lose time on every late wakeup and grow latency.

### 4. Controlled catch-up
When a timer fires late, MisMeeter sends a small bounded number of already-due VBAN packets.
This lets the sender recover average throughput without producing a huge 100 ms callback burst.

### 5. Adaptive latency
Auto still lowers the target after stable windows and restores safety quickly after underruns.

## New diagnostics

- Adaptive target
- Capture rate
- TX rate
- Scheduler late
- Catch-up packets
- Underruns
- Packets sent

A healthy result should look roughly like:

- Capture rate close to 48,000 Hz
- TX rate close to Capture rate
- Sender buffer oscillating around the target rather than growing indefinitely
- Underruns = 0
- Catch-up packets can increase slowly; that is expected

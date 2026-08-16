# MisMeeter v1.1 — Lock Transition + Adaptive Background Batch

v1.1 is focused specifically on the pattern observed on-device:

- audio is excellent in foreground
- a large disturbance occurs while the phone locks
- after lock, some periods are smooth and others become fragmented

## Three transport states

### Foreground Realtime
- batch = 1
- 256 samples
- minimum latency

### Lock Transition
Triggered by SwiftUI scenePhase `.inactive`.

Important: v1.1 DOES NOT switch to background batching here.

It keeps:
- batch = 1
- realtime packet behaviour

This avoids changing network timing at the same moment iOS is performing the lock transition.

### Background Stable
Triggered only by scenePhase `.background`.

Starts at:
- batch = 4
- 1024 samples
- ~21.33 ms audio per queue wakeup

## Adaptive background batch

Every 5 seconds MisMeeter examines the maximum interval observed between packet sends.

If max send gap > ~35 ms:
- 4 -> 6 packets
- then 6 -> 8 packets

If the stream remains stable with max gaps < ~24 ms for ~15 seconds:
- 8 -> 6
- then 6 -> 4

This allows the sender to react to changing iOS background/network scheduling without permanently
using the largest possible batch.

## New diagnostics

- Transport state
- VBAN batch
- Batch buffer
- Max send gap

Existing diagnostics remain:
- Input callback
- Actual I/O buffer
- Capture rate
- TX rate
- Underruns
- Packets sent

## Existing features retained

- AVAudioSinkNode realtime capture
- Apple Voice Processing toggle
- 3 VBAN presets
- software gain
- Live Activity / Dynamic Island mute
- direct VBAN UDP
- 48 kHz PCM16 mono

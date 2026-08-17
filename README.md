# MisMeeter v1.3 — Duplex VBAN

MisMeeter can now operate in both directions independently.

## MIC -> VBAN

Existing transmitter:

iPhone microphone -> VBAN UDP -> VoiceMeeter

Features retained:
- 3 TX presets
- gain 0...+24 dB
- Apple Voice Processing
- Live Activity / Dynamic Island
- mute
- direct realtime UDP

## VBAN -> iPhone

New independent receiver:

VoiceMeeter VBAN OUT -> UDP -> MisMeeter -> iPhone speaker

Features:
- 3 completely separate RX presets
- each RX preset stores:
  - name
  - local UDP listen port
  - VBAN stream name
  - jitter-buffer size
- PCM16 48 kHz
- mono streams duplicated to L/R
- stereo streams preserved
- realtime AVAudioSourceNode playback
- jitter buffer with automatic re-prime after an underflow
- packet/loss/underflow diagnostics

TX and RX can be:
- both OFF
- TX only
- RX only
- TX + RX simultaneously

## VoiceMeeter RX setup

To listen on the iPhone:

1. Find the iPhone LAN IPv4 address.
2. In VoiceMeeter VBAN OUT create/enable a stream.
3. Destination IP = iPhone IPv4.
4. Destination port = selected MisMeeter RX preset port.
5. Stream Name = exact MisMeeter RX stream name.
6. Use 48 kHz PCM16 mono or stereo.
7. Press Start Listening in MisMeeter.

If Wi-Fi jitter is audible, increase the RX preset Jitter Buffer slider.
Start around 100 ms.

## Audio-session coexistence

When microphone TX is active, MisMeeter uses playAndRecord so speaker RX can run at the same time.
Stopping TX does not deactivate the iOS audio session when RX is still active, and stopping RX does
not deactivate it while TX is still active.


## v1.3.1 build fix

- Fixed Swift exclusivity error in `VBANReceiver.drainSocket()` by caching packet capacity before `withUnsafeMutableBytes`.
- Removed Swift 6 `UnsafeMutablePointer` Sendable warnings from `PlaybackRingBuffer.render()` by keeping caller output pointers outside the lock closure.


## v1.4 RX Smooth

The VBAN -> iPhone receiver now performs clock recovery.

The PC sender clock and iPhone speaker clock are never exactly identical. A fixed jitter buffer can
therefore slowly drain or fill even when the network has zero packet loss.

v1.4 inserts AVAudioUnitVarispeed between the receiver source and the iPhone output and automatically
adjusts playback between 0.995x and 1.005x according to ring-buffer occupancy.

It also uses an adaptive jitter target:
- underflow: +20 ms immediately, up to 300 ms
- 15 seconds stable: -10 ms toward the preset's configured buffer

New RX diagnostics:
- Clock correction
- Adaptive target


## v1.5 Stability

### RX
- Fixes a real re-prime bug: when the adaptive jitter target rises above the currently buffered
  audio, playback is now paused until the new target is genuinely rebuilt.
- Replaces AVAudioUnitVarispeed with AVAudioUnitTimePitch for pitch-preserving clock correction.
- Clock servo can correct from 0.98x to 1.02x when the buffer is far from target.
- Underflow raises target by 50 ms immediately, up to 600 ms.
- Stable target reduction is intentionally slower.

### TX lock-screen experiment
A new `Lock-screen TX stabilizer` (enabled by default) adds a completely silent AVAudioSourceNode to
the microphone AVAudioEngine output path. The engine's own mixer remains muted. This keeps both sides
of the `playAndRecord` hardware I/O graph rendering while the iPhone is locked, while VBAN still uses
the direct nonblocking UDP sender.

This can consume more battery. It can be disabled from the app when TX is stopped.


## v1.6 RemoteIO Capture

The receiver path from v1.5 is retained unchanged because on-device testing showed it is stable both
foreground and locked.

### Microphone TX
AVAudioSinkNode has been replaced by the lower-level Apple RemoteIO Audio Unit:
- RemoteIO when Apple Voice Processing is OFF
- VoiceProcessingIO when Apple Voice Processing is ON
- input bus 1 enabled
- mono Float32 48 kHz rendered directly with AudioUnitRender
- VBAN sender remains direct nonblocking UDP

New diagnostic:
- `Mic callback max gap`

This is specifically intended to distinguish a true microphone/capture scheduling interruption from
a network-send interruption when the screen locks.

### Speaker routing
A shared AudioSessionCoordinator configures `.playAndRecord + .defaultToSpeaker` and explicitly calls
`overrideOutputAudioPort(.speaker)` when TX/RX are started. This prevents simultaneous RX+TX from
falling back to the iPhone telephone receiver.


## v1.7 Capture Lab

Receiver path is unchanged from the stable v1.5/v1.6 implementation.

TX microphone capture now has two selectable engines:
- RemoteIO Raw
- VoiceProcessingIO

The Core Audio callback no longer performs VBAN transmission. It only:
1. calls AudioUnitRender
2. converts Float32 to PCM16 using preallocated scratch buffers
3. writes PCM16 into a preallocated capture ring
4. returns

A separate high-priority worker drains that ring and feeds the existing direct UDP VBAN sender.

New lock-screen diagnostics:
- Mic callback max gap (monotonic wall clock)
- gaps >10 ms
- gaps >15 ms
- gaps >25 ms
- gaps >50 ms
- capture ring frames
- capture overruns

These counters persist across screen lock so after unlocking it is clear whether capture itself was
interrupted or whether the problem happened after capture.

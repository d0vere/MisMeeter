# MisMeeter v1.2 — Direct Realtime UDP

## Why this version

On-device diagnostics showed:

- Core Audio callback: 256 frames / 5.33 ms
- Underruns: 0
- Max network send gap after lock: ~88 ms

Therefore microphone capture is healthy while the ordinary networking queue is occasionally not
scheduled for many audio periods after screen lock.

## Realtime UDP experiment

v1.2 removes Network.framework from the packet send hot path.

Before streaming:
- create an IPv4 UDP socket
- connect it to the configured VBAN destination
- mark it O_NONBLOCK
- increase SO_SNDBUF
- preallocate the 540-byte VBAN packet buffer

During each 256-frame AVAudioSinkNode callback:
- update the preallocated VBAN header/frame counter
- copy PCM16 samples
- call nonblocking send()

No GCD networking queue is required for the actual packet submission.

This is intentionally an aggressive realtime experiment. The socket is nonblocking so the audio
thread never waits for the network. A failed/EAGAIN send is counted in Underruns/Errors rather than
blocking Core Audio.

Important: v1.2 realtime UDP requires an IPv4 address in presets. Hostname resolution is intentionally
not performed on the audio thread.

## Live Activity force-quit behaviour

Apple intentionally keeps Live Activities independent of the host app process, so force-quitting the
app does not automatically dismiss them.

v1.2 improves the UX in two ways:
1. On the next app launch, any orphan Live Activity is ended automatically when VBAN is not running.
2. The Live Activity now includes an END button that asks ActivityKit to dismiss it immediately.

There is no reliable public iOS callback that guarantees cleanup at the exact moment the user
force-quits an already-backgrounded app.

## Existing features retained

- AVAudioSinkNode realtime microphone
- Apple Voice Processing
- 3 VBAN presets
- software gain
- Live Activity / Dynamic Island mute
- 48 kHz PCM16 mono

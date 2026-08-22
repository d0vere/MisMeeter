# MisMeeter 4.0.4 — R3 / build 106

## Control Center
Fixes the remaining lifecycle race: `applicationDidEnterBackground` no longer publishes a newly-created idle runtime. A `LiveActivityIntent` can cold-launch the process directly into the background, so that callback must not overwrite the App Group snapshot used by `ControlValueProvider`.

## TX while RX is already active
The RX `AVAudioEngine` is now temporarily quiesced before transitioning `AVAudioSession` from receive-only playback to duplex play-and-record. TX establishes its microphone Audio Unit first; RX is then rebuilt under the duplex session and its mute state is restored. On TX startup failure, RX is restored best-effort. This avoids changing the session category underneath a running output graph, which was the new path introduced by the duplex/session hardening.

## Diagnostics
Microphone Audio Unit errors now include the exact configuration stage (`enable-input`, `disable-output`, `stream-format`, `maximum-frames`, `input-callback`, `initialize`, or `start`) so any remaining device-specific failure is actionable.

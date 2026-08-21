# MisMeeter 3.3.0 — Senior iOS review

## Lock Screen / Now Playing

The 3.2.9 implementation could lose an active Now Playing claim after microphone mute because the silent `AVAudioPlayer` was actually paused. It also disabled Now Playing whenever a Bluetooth input was merely available, which could suppress controls even when the iPhone speaker was the active route.

3.3.0 moves the media surface to `AVQueuePlayer` + `AVPlayerLooper` + `MPNowPlayingSession`. The silent WAV remains physically playing for the lifetime of active TX. Microphone mute/unmute is represented as logical playback metadata instead of stopping the keep-alive player. Remote commands are registered on the session-specific command center and the session is promoted with bounded retries.

Mappings:

- Play: microphone unmute (only if TX is already active)
- Pause: microphone mute
- Toggle Play/Pause: microphone mute toggle
- Previous: RX mute toggle
- Next: Stop All

The controller observes audio-route changes, interruptions, and media-services resets. Bluetooth/car/AirPlay routes in actual use make MisMeeter yield Now Playing. A newly discovered external accessory also gets a short 6-second grace period so an automotive/media player can claim media controls first, without permanently disabling Lock Screen controls just because a paired Bluetooth input remains available.

## Automatic jitter

The manual RX jitter preset has been removed. The receiver now starts at 35 ms and continuously estimates packet-arrival deviation. Its target combines a four-packet base runway with measured smoothed/peak network jitter and an adaptive safety margin.

- Minimum target: 20 ms
- Startup target: ~35 ms
- Maximum target: 250 ms
- Underflow: +25 ms safety margin immediately
- Stable playback: safety margin decreases by 5 ms after each 10-second clean window
- Playback clock recovery remains ±2% through `AVAudioUnitTimePitch`

Target increases caused by measured jitter do not forcibly re-prime playback unless an actual underflow occurred, avoiding unnecessary audible gaps.

## RX allocation reduction

The packet decoder now reuses two 256-frame Float scratch arrays instead of allocating/reserving two new arrays for each packet. At 48 kHz / 256 samples this removes roughly 187 pairs of array allocations per second.

## Validation performed in this package

- Swift syntax parse on every `.swift` source file
- YAML parse for `project.yml` and GitHub Actions workflow
- JSON parse for every asset catalog JSON file
- plist validation for app/widget entitlements
- ZIP integrity test after packaging

A true semantic iOS build and Lock Screen behavior test still require Xcode 16.4/iOS 18.5 and a signed physical iPhone; those Apple SDK/runtime components are not available in this Linux validation environment.

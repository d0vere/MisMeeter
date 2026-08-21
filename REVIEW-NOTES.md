# MisMeeter 3.3.3 — Dynamic Island + authoritative native Controls

- Dynamic Island compact presentation now groups both RX and TX icons on the leading/left side of the camera area.
- Inactive RX/TX indicators remain visible but dimmed, avoiding layout jumps.
- Compact trailing region is intentionally empty; no microphone icon can be clipped on the right edge.
- Reworked Mic and RX Controls to expose ON / MUTED / IDLE and disable interaction when the corresponding transport is inactive.
- Control intents no longer write optimistic transport state from the extension.
- Exact-value commands are sent to the running runtime, followed by a short acknowledgement readback from the App Group snapshot.
- Live Activity mute intents now use the same runtime-authoritative command path.
- Stop All waits for runtime confirmation before dismissing the Live Activity.
- App-side state changes continue to trigger targeted Control Center reloads.
- No MediaPlayer / Now Playing / silent-player implementation or audio resource remains.
- Automatic adaptive RX jitter remains unchanged.
- Version 3.3.3, build 45.

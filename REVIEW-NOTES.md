# MisMeeter 3.3.8 review notes

- Reworked Control Center controls as native `ControlWidgetToggle` mute switches.
- ON means muted; muted controls render with red tint and slashed symbols.
- Added `SetMicrophoneMuteControlIntent` and `SetReceiveMuteControlIntent` as `SetValueIntent + LiveActivityIntent`.
- Control intents execute in the app process and call `MisMeeterRuntime` directly; no App Group command mailbox or Darwin command bridge is required.
- Live Activity mute/stop intents now also act directly on `MisMeeterRuntime` in the app process.
- Removed `SharedControlObserver`, command mailbox files, command IDs, and command polling.
- Fixed stale cross-process snapshots by adding `publishedAt` and selecting the newest valid file/UserDefaults copy.
- Bumped the shared snapshot namespace to v8 so stale v7 files cannot shadow current state.
- Control providers prefer the active ActivityKit content state, matching the Dynamic Island, with App Group state as fallback.
- RX speaker/audio-session recovery and adaptive jitter behavior are unchanged.

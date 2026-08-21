# MisMeeter 3.3.9 review notes

- Reworked Control Center controls as native `ControlWidgetToggle` mute switches.
- ON means muted; muted controls render with red tint and slashed symbols.
- Added `SetMicrophoneMuteControlIntent` and `SetReceiveMuteControlIntent` as `SetValueIntent + LiveActivityIntent`.
- Control intents execute in the app process and call `MisMeeterRuntime` directly; no App Group command mailbox or Darwin command bridge is required.
- Live Activity mute/stop intents now also act directly on `MisMeeterRuntime` in the app process.
- Removed `SharedControlObserver`, command mailbox files, command IDs, and command polling.
- Fixed stale cross-process snapshots by adding `publishedAt` and selecting the newest valid file/UserDefaults copy.
- Bumped the shared snapshot namespace to v8 so stale v7 files cannot shadow current state.
- Control providers read the synchronously-published App Group snapshot only; ActivityKit is presentation-only.
- Fixed the one-interaction lag where an asynchronous Live Activity update caused a second tap to send the same mute value again.
- RX speaker/audio-session recovery and adaptive jitter behavior are unchanged.
- Fixed RX mute publication ordering: `_isReceiveMuted` is committed before `VBANReceiver.setOutputMuted()` can emit a synchronous status callback.
- Control intents wait for the matching Live Activity update before returning, while Control Center itself reads the already-committed App Group snapshot.

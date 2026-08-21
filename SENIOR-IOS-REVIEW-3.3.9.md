# MisMeeter 3.3.9 — Control Center State Synchronization Review

Version: 3.3.9 (build 51)

## Fixed

- Control Center no longer derives Mic/RX toggle state from ActivityKit.
- The ControlValueProvider now reads only the authoritative App Group snapshot written synchronously by `MisMeeterRuntime`.
- This removes a race where `SetValueIntent.perform()` returned before the Live Activity update completed, causing WidgetKit to re-query the old mute value and send the same value on the next tap.
- RX/TX mute controls remain native `ControlWidgetToggle` controls: mute is the ON state, so muted renders as the highlighted red state with a slashed SF Symbol.
- Runtime state remains authoritative; ActivityKit is presentation-only.
- RX mute state is committed before the receiver emits its synchronous status callback, eliminating a second stale-state refresh race.
- Control intents wait for the Live Activity synchronization before returning, so Control Center and Dynamic Island converge on the same final state without relying on timing.

## Expected interaction

1. RX active/unmuted -> toggle OFF, speaker icon normal.
2. Tap once -> runtime applies mute, snapshot is synchronously written, toggle becomes ON/red/slashed.
3. Tap again -> runtime applies unmute, snapshot is synchronously written, toggle becomes OFF/normal.
4. No double-tap timing dependency.

## Architecture

`ControlWidgetToggle -> SetValueIntent + LiveActivityIntent -> MisMeeterRuntime -> SharedAppState.writeSnapshot() -> ControlValueProvider.currentValue()`

ActivityKit is updated afterwards for Dynamic Island/Live Activity presentation, but is deliberately not used as the Control Center source of truth.

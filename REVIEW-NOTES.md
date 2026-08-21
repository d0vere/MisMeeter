# MisMeeter 4.0.1 review notes

## Scope

4.0.1 is a state-synchronization stabilization release over 4.0.0. VBAN transport, RX speaker recovery, adaptive jitter, audio-session policy, Dynamic Island layout and Control tap semantics are preserved.

## Control Center synchronization fixes

- `SharedControlState` now contains `txActive`, `txMuted`, `rxActive` and `rxMuted` in one atomic revision.
- The control provider no longer receives only a mute Bool; it receives active + mute presentation state so ACTIVE and IDLE can render differently.
- Mute remains the actual `ControlWidgetToggle` Boolean: `false = unmuted`, `true = muted`.
- Muted remains the system ON state and uses red tint with a slashed SF Symbol.
- Active-unmuted uses a filled microphone/speaker symbol; idle uses the neutral outline symbol.
- Every state mutation outside the interacted Control writes the complete atomic control state and then calls `ControlCenter.shared.reloadAllControls()`.
- RX and TX are deliberately reloaded together because they share one revision and there are only two controls; this avoids visual skew with negligible overhead.
- `SetValueIntent` handlers still do **not** manually reload Control Center. WidgetKit performs its documented post-`perform()` reload for the interacted control.
- App launch republishes the newly-created runtime state and reloads controls before the main UI appears, clearing cached state left by an earlier process.
- Entering background republishes/reloads the current state without stopping valid background audio.
- `applicationWillTerminate` performs best-effort IDLE publication and reload before normal process termination.

## Important iOS lifecycle limitation

Apple does not guarantee `applicationWillTerminate` for every force-quit/background termination of a background-capable app. Therefore no local-only iOS app can guarantee an immediate visual Control Center refresh after every externally-forced process death; configured controls update when interacted with, when the app asks `ControlCenter` to reload them, or through Control push updates. 4.0.1 covers all app-controlled state transitions and all lifecycle callbacks iOS actually delivers.

## Preserved behavior

- Dynamic Island remains ActivityKit-only; no Now Playing / MediaPlayer session exists.
- Compact Dynamic Island keeps RX + TX together on the leading side.
- RX-only uses `.playback`; duplex uses `.playAndRecord` with speaker routing.
- RX route/interruption/configuration recovery remains enabled.
- Adaptive jitter remains automatic and unchanged.
- Control intents remain `.alwaysAllowed` and `openAppWhenRun = false`.

## Build discipline

- XcodeGen source membership remains explicit.
- CI regenerates the Xcode project from scratch.
- CI targets Xcode 16.4 / iOS 18.5 Release and rejects Swift warnings.
- CI asserts the external-reload contract, v4.0.1 active/mute state schema and absence of legacy media components.

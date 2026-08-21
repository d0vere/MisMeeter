# MisMeeter 4.0.2 review notes

4.0.2 is a focused Control Center synchronization release over 4.0.1. The VBAN transport, adaptive jitter, audio-session policy, RX speaker recovery, Live Activity/Dynamic Island layout and SetValueIntent tap behavior are intentionally unchanged.

## Control Center synchronization

- RX/TX Controls no longer maintain a second `SharedControlState` data file.
- `SharedAppState` (`transport-state-v4.json`) is now the single authoritative App Group snapshot for the app, widgets, Live Activity presentation and Control Center rendering.
- The Controls use `StaticControlConfiguration` without a `ControlValueProvider`; every requested Control reload rebuilds the template and reads `SharedAppState` directly in the widget extension.
- External runtime mutations invalidate the exact configured Control kinds with `ControlCenter.shared.reloadControls(ofKind:)` for RX and TX.
- A Control tap still relies on WidgetKit's automatic reload after `SetValueIntent.perform()` completes; no competing manual reload is issued from the interacted intent.

## Preserved behavior

- RX/TX mute commands execute in the app process through `SetValueIntent + LiveActivityIntent`.
- `authenticationPolicy = .alwaysAllowed` remains unchanged for locked-device use.
- Muted is the toggle ON state and uses red tint plus the slashed SF Symbol.
- The v4 Control `kind` identifiers remain unchanged, preserving existing placements.
- No Now Playing, MediaPlayer or silent-audio workaround is present.

## Process termination limitation

A force-quit can terminate a background-capable process without a guaranteed final lifecycle callback. iOS only refreshes a Control after interaction, an app-requested reload, or a Control push. 4.0.2 guarantees app-originated state synchronization while the app process is able to request the documented reload; it does not claim an API capability that iOS does not provide after an unannounced process kill.

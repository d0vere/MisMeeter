# MisMeeter 3.3.6 — Senior iOS review

## Control Center / Lock Screen state semantics

The previous implementation used `ControlWidgetToggle`. That template has true system ON/OFF semantics, and iOS intentionally de-emphasizes the OFF presentation. For MisMeeter that is misleading: a muted transport is not idle; it is an active transport in an important safety/operational state.

3.3.6 therefore uses `ControlWidgetButton` with a `ControlValueProvider`. The button action still toggles the applied mute state, while the provider renders the latest runtime-owned snapshot independently of the action:

| Runtime state | TX Control | RX Control |
| --- | --- | --- |
| Active / audible | green `mic.fill` | green `speaker.wave.3.fill` |
| Active / muted | red `mic.slash.fill` | red `speaker.slash.fill` |
| Idle | neutral + disabled | neutral + disabled |

This model also avoids depending on WidgetKit's toggle OFF styling for an operational status indicator.

## State authority

The main MisMeeter runtime remains authoritative. Controls never write an optimistic visual snapshot. A press invokes `ToggleMuteIntent` or `ToggleReceiveMuteIntent`, which reads the latest shared runtime snapshot, requests the exact opposite mute value through the action mailbox, waits briefly for runtime acknowledgement, and asks Control Center to reload the affected control.

When mute state changes from inside the app, `SharedAppState.writeSnapshot` detects the state transition and reloads the matching Control Center kind.

## Compatibility

The existing control `kind` identifiers are unchanged. This is intentional so a user's already configured Control Center / Lock Screen controls can refresh to the new implementation without being treated as entirely new controls. At app launch, 3.3.6 also calls `ControlCenter.shared.reloadAllControls()` so the system rebuilds cached control templates after an upgrade.

The exact-value `SetMicrophoneEnabledIntent` and `SetReceiveEnabledIntent` sources are removed because they were specific to the old `ControlWidgetToggle` architecture and are no longer referenced.

## RX path

The receive-path corrections from 3.3.5 remain unchanged: RX-only uses `AVAudioSession.Category.playback`; duplex operation uses `.playAndRecord` with speaker routing; and the receiver rebuilds/restarts output after relevant route, interruption, and audio-engine configuration changes. Adaptive receive jitter remains enabled.

## Validation performed in this package

- Swift parser validation across every shipped `.swift` source.
- YAML validation for `project.yml` and GitHub Actions.
- JSON validation for asset catalogs.
- plist validation for app and widget entitlements.
- Explicit source-manifest check: every source referenced by `project.yml` exists.
- Orphan-source check: every shipped Swift source is intentionally represented in a target.
- Legacy-media scan for removed Now Playing/silent-audio components.
- Control architecture scan rejects the removed `ControlWidgetToggle` and SetValue-intent files.

A real Xcode 16.4 / iOS 18.5 Release compile is still performed by the included GitHub Actions workflow because Apple SDK type checking cannot be executed in this Linux packaging environment.

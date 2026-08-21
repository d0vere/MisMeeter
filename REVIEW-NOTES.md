# MisMeeter 3.3.6 — Control state presentation fix

## Fixed

- Replaced `ControlWidgetToggle` for TX/RX with state-aware `ControlWidgetButton` controls.
- Muted is no longer presented as a dim/neutral OFF toggle.
- TX muted is rendered red with `mic.slash.fill`.
- RX muted is rendered red with `speaker.slash.fill`.
- Active TX/RX is rendered green with the normal active symbol.
- Idle controls remain neutral and disabled.
- Control actions continue to read the latest runtime snapshot and toggle the real applied state.
- Kept the existing control kind identifiers so users should not need to re-add the controls after upgrading.
- Added `ControlCenter.shared.reloadAllControls()` at app launch so installed controls rebuild the new button template immediately after an upgrade.
- Removed the now-unused `SetMicrophoneEnabledIntent` and `SetReceiveEnabledIntent` sources.

## Preserved from 3.3.5

- RX-only `.playback` audio-session policy.
- Duplex `.playAndRecord` + speaker routing.
- Audio-engine route/interruption/configuration recovery.
- Adaptive low-latency receive jitter.
- Dynamic Island RX + TX compact-leading layout.
- Explicit XcodeGen source membership and legacy-source CI guards.

Version 3.3.6, build 48.

# MisMeeter 4.0.4 review notes

4.0.4 fixes the Control Center regression introduced in 4.0.3 while retaining the synchronization hardening added after 4.0.2.

## Confirmed 4.0.3 regression

4.0.3 applied `.disabled(!value.isActive)` to both `ControlWidgetToggle` templates. If WidgetKit rendered from an IDLE or temporarily stale provider snapshot, SpringBoard disabled the Control itself. In that state the tap never reached `SetValueIntent.perform()`, so there was no optimistic toggle feedback and no runtime mutation.

## 4.0.4 Control Center model

- RX/TX Controls remain backed by `ControlValueProvider` and read the authoritative atomic App Group snapshot.
- Transport activity (`isActive`) affects labels/status only; it never disables tap delivery.
- Runtime guards remain authoritative and reject mute changes when the corresponding transport is inactive.
- App-originated start/stop/mute changes persist state before invalidating the exact configured Control kinds.
- Control interactions rely on WidgetKit's automatic refresh after `SetValueIntent.perform()` returns.
- Launch/foreground recovery calls `ControlCenter.shared.reloadAllControls()` to evict templates cached from 4.0.3.
- Existing v4 Control kind identifiers remain unchanged to preserve Control Center placements.

## Synchronization hardening retained

- Runtime snapshots are captured atomically from one `stateQueue.sync`.
- Snapshot capture + App Group publication are serialized, preventing older callbacks from overwriting newer transport fields.
- Persisted snapshots normalize impossible mute states while a transport is stopped.
- SwiftUI receives authoritative runtime snapshot callbacks for changes initiated from system Controls.

## Validation scope

`Scripts/validate-package.sh` parses every Swift source, validates YAML/JSON/plist files, verifies target source membership, and asserts the Control Center architecture including the absence of `.disabled(...)` in `MisMeeterSystemControls.swift`. The included GitHub workflow is configured for Xcode 16.4 / iOS 18.5 Release compilation with Swift warnings treated as errors.

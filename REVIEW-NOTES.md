# MisMeeter 4.0.3 review notes

4.0.3 corrects the Control Center state model used by 4.0.2 and hardens synchronization between the audio runtime, App Group snapshot, system controls and in-app SwiftUI state.

## Root cause fixed

4.0.2 created `StaticControlConfiguration` without a `ControlValueProvider` and captured `SharedAppState.readSnapshot()` while constructing the configuration body. This bypassed WidgetKit's documented current-value lifecycle for stateful controls and could leave Control Center rendering stale TX/RX state after app-originated transport changes.

## 4.0.3 Control Center model

- RX/TX controls now use `ControlValueProvider`.
- `currentValue()` reads the authoritative atomic App Group snapshot.
- Provider values contain both `isActive` and `isMuted`, so IDLE/ACTIVE and mute feedback come from the same snapshot.
- Controls are disabled while their transport is inactive.
- App-originated start/stop/mute changes reload the exact configured Control kinds.
- Control interactions still rely on WidgetKit's automatic refresh after `SetValueIntent.perform()`; no competing manual reload is performed inside the intent.
- A stale in-flight tap against an already-stopped transport now republishes the authoritative inactive snapshot before the intent returns.

## Additional synchronization hardening

- Runtime snapshots are captured atomically from one `stateQueue.sync`, preventing mixed TX/RX fields from separate reads.
- Snapshot capture + App Group publication are serialized so an older callback cannot overwrite newer transport fields.
- Persisted snapshots normalize impossible states (`muted == true` while the corresponding transport is stopped).
- Runtime publishes a transport snapshot callback so the SwiftUI UI immediately reconciles changes initiated from Control Center.
- Existing v4 Control `kind` identifiers remain unchanged to preserve user placements.

## Preserved behavior

VBAN encoding/decoding, adaptive RX jitter, audio-session policy, background audio, Live Activity geometry and the existing mute semantics are otherwise unchanged.

## Validation scope

`Scripts/validate-package.sh` performs Swift parser checks plus architecture/source-membership assertions. The GitHub workflow generates a fresh Xcode project with XcodeGen and is configured to build an unsigned Release app with Xcode 16.4 / iOS 18.5 while rejecting Swift compiler warnings.

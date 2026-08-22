# MisMeeter 4.0.4 — Control Center R2

Build 105 fixes a process-launch race affecting iOS 18 Control Center toggles.

## Root cause addressed
`LiveActivityIntent` executes in the app process. When iOS had to launch that process to service a Control Center action, runtime/app launch code published the default idle runtime into the App Group before `perform()` completed. WidgetKit later queried `ControlValueProvider.currentValue()`, saw the overwritten snapshot, and the optimistic toggle could snap back.

## Changes
- Runtime initialization no longer writes an idle shared snapshot as a side effect.
- Process launch invalidates cached controls without publishing runtime state.
- Normal foreground/runtime reconciliation still publishes authoritative state.
- TX/RX Control intents log requested and persisted mute values for device diagnostics.
- Build incremented from 104 to 105.

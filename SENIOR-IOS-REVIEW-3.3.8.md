# MisMeeter 3.3.8 — Control Center architecture review

## Root cause addressed

3.3.7 could display `RX is not running` while the Live Activity showed RX active because the Control Center provider and ActivityKit were reading different state paths. The shared-state reader also preferred any decodable App Group file, even if that file was older than the UserDefaults copy.

## New control architecture

The two iOS 18 Controls now follow Apple's stateful control pattern:

- `ControlWidgetToggle`
- `SetValueIntent`
- `LiveActivityIntent`

Mute is the boolean represented by the system toggle. Therefore an ON control means mute is engaged. The muted state uses a red tint with `mic.slash.fill` or `speaker.slash.fill`, matching the native Silent Mode interaction model.

Because the SetValue intents also conform to `LiveActivityIntent`, iOS executes them in the app process. The intent therefore calls `MisMeeterRuntime.shared` directly and does not depend on Widget Extension state, a command mailbox, or a Darwin notification to control the running audio engine.

## State resolution

Control rendering uses two sources:

1. Active/stale ActivityKit content when a MisMeeter Live Activity exists.
2. App Group snapshot fallback.

The App Group snapshot has a `publishedAt` value. Both the atomic JSON file and UserDefaults representation are decoded and the newest copy wins. The shared namespace is v8, preventing old v7 data from being selected after an upgrade.

## Removed complexity

- `SharedControlObserver`
- per-action command mailbox JSON files
- command IDs and command replay filtering
- snapshot polling acknowledgements
- Control Center actions that first guessed the next state from a potentially stale extension snapshot

The audio runtime remains the authoritative owner of RX/TX state and republishes state after every applied change.

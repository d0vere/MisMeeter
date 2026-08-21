# MisMeeter 3.3.3 — Senior iOS review

## System-surface architecture

MisMeeter keeps a single system presentation model:

- **ActivityKit** owns the Live Activity and Dynamic Island.
- **WidgetKit Controls** own Control Center / Lock Screen quick actions.
- **App Intents** request exact runtime state changes with `.alwaysAllowed` and `openAppWhenRun = false`.
- **App Group + Darwin notification** bridge the extension request to the already-running audio runtime.

There is no `MediaPlayer`, Now Playing session, silent WAV, or remote-command workaround.

## Dynamic Island

The compact Dynamic Island now places both transport indicators in `compactLeading`, which is the area to the left of the camera/sensor region. RX and TX use small fixed-size SF Symbols with a stable two-icon footprint. The trailing compact region is empty, eliminating the previous right-edge microphone clipping path.

Expanded mode also keeps both RX/TX status badges in the leading region and reserves the trailing region for text-only status.

## Control Center / Lock Screen state model

The Controls use `ControlWidgetToggle` with custom `ControlValueProvider` values containing both the rendered ON/OFF value and transport availability.

- Mic ON -> TX active and unmuted
- Mic OFF -> TX active and muted
- Mic IDLE -> TX not active; control disabled
- RX ON -> receiver active and audible
- RX OFF -> receiver active and muted
- RX IDLE -> receiver not active; control disabled

The `SetValueIntent` does not mutate the shared snapshot optimistically. It issues an exact desired command to the running audio runtime and waits briefly for the runtime to publish the applied state. The control is then reloaded from that authoritative snapshot. If the runtime does not apply the request, the UI returns to the real previous state instead of displaying a false toggle.

Live Activity mute buttons use the same non-speculative command path. Stop All similarly waits for an idle acknowledgement before dismissing the ActivityKit presentation.

## Validation performed

- Swift parser validation across all source files
- JSON asset validation
- YAML validation for `project.yml` and GitHub Actions
- stale MediaPlayer / Now Playing / silent-audio scan
- package integrity validation

A physical iPhone test remains required for final SpringBoard placement and Control Center / Lock Screen behavior because those surfaces are rendered and arbitrated by iOS.

# MisMeeter 4.0.0 review notes

## Stabilization scope

Version 4.0.0 is a clean stabilization pass over the 3.3.9 source tree. The VBAN transport, adaptive RX jitter algorithm, RX speaker recovery and ActivityKit presentation are preserved unless a correctness issue required a change.

## Control Center / Lock Screen controls

- Rebuilt RX and TX mute controls around Apple's WWDC24 reference pattern: `ControlWidgetToggle` + `SetValueIntent` + `LiveActivityIntent`.
- Toggle semantics are intentionally simple: `false = unmuted`, `true = muted`.
- Muted is the system ON state, so `.tint(.red)` produces a highlighted red mute control with a slashed SF Symbol.
- Each `ControlValueProvider` returns a single `Bool`; transport running/idle metadata cannot affect or freeze the toggle value.
- `SetValueIntent.value` is treated as the final desired mute state. There is no manual inversion and no blind toggle command.
- The intent runs in the app process and calls the authoritative `MisMeeterRuntime` directly without opening the UI.
- The runtime commits the mute bit first, applies it to the audio engine, writes the App Group control-state file synchronously, and only then lets the intent complete.
- There is no `ControlCenter.reloadControls` call in either control intent. WidgetKit performs the post-interaction reload automatically after `perform()` returns.
- Manual control reloads are used only when state changes from the main app/runtime rather than from the interacted control.
- RX and TX control commands are serialized independently, so rapid interactions cannot race the audio mute mutation inside one channel.
- v4 uses new unique Control `kind` identifiers to prevent cached 3.x templates/state from contaminating the new implementation.
- `.alwaysAllowed` remains explicit so the intents are eligible to run while the device is locked.

## Cross-process state

- Added `SharedControlStateStore`, separate from the richer widget/Live Activity snapshot.
- Control state contains only `txMuted`, `rxMuted`, revision and publication time.
- The app is the only writer; the widget extension is read-only.
- State uses an atomic JSON file in the shared App Group container.
- File protection is `completeUntilFirstUserAuthentication`, allowing access again while the device is locked after its first unlock since boot.
- Removed dual file/UserDefaults arbitration from transport state; v4 has one authoritative App Group file per state domain.
- Lower-level transmitter/receiver status callbacks cannot write the control-state store.

## Runtime correctness

- System-control mute requests set an exact desired value rather than toggling based on a potentially stale snapshot.
- RX commits `_isReceiveMuted` before calling `VBANReceiver.setOutputMuted`, preventing the receiver's synchronous status callback from publishing the previous value.
- RX startup failure now clears the runtime's receive-active state because rebuilding the receiver tears down the previous receiver first.
- App-originated mute changes write state before requesting the matching Control Center refresh.
- System-control changes deliberately avoid a manual refresh during the intent transaction.

## Existing functionality preserved

- ActivityKit remains the only Dynamic Island / Live Activity presentation surface.
- Compact Dynamic Island keeps RX + TX together on the leading side.
- No Now Playing / MediaPlayer / silent-audio workaround exists in v4.
- RX-only playback uses the playback audio-session policy; duplex uses play-and-record with speaker routing.
- RX engine recovery for route changes, interruptions and AVAudioEngine configuration changes remains enabled.
- Adaptive jitter behavior remains automatic with the existing low-latency floor and stability recovery logic.

## Build discipline

- `project.yml` uses explicit source membership for both targets; stale files copied into a repository cannot silently enter the build.
- CI deletes and regenerates the Xcode project with XcodeGen before every build.
- CI performs a real unsigned Release device build with Xcode 16.4 / iOS 18.5.
- CI rejects Swift compiler warnings and scans the final binary for removed Now Playing components.
- CI contains explicit assertions for the v4 Control architecture and anti-race rules.

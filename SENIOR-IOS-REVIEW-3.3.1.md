# MisMeeter 3.3.1 — Senior iOS review

## Lock Screen microphone state

The 3.3.0 keep-alive player intentionally stays physically playing so iOS retains an eligible Now Playing session. That means the system media icon can remain visually in a playing state even after the microphone is muted from the app. Mapping Pause to “force mute” therefore allowed a stale Lock Screen control to apply mute twice.

3.3.1 removes that assumption. `playCommand`, `pauseCommand`, and `togglePlayPauseCommand` all invoke one atomic runtime microphone toggle. The VBAN runtime remains the source of truth, so a microphone state change from the app, Live Activity, Control Widget, or Lock Screen cannot make the next media-button press repeat the same state. Previous Track remains RX mute toggle and Next Track remains Stop All. Remote media commands still require an already-active TX session.

## Dynamic Island arbitration

ActivityKit and Now Playing are separate system surfaces. iOS can temporarily present both when the media session is promoted while a Live Activity is active. There is no supported public API to request “Now Playing on Lock Screen only, never in Dynamic Island.”

The package therefore uses a best-effort ordering strategy instead of private APIs:

- establish/update the Live Activity before starting Now Playing promotion;
- when `MPNowPlayingSession` successfully becomes active, immediately reassert the Live Activity;
- send a second distinct ActivityKit update after the short promotion race window;
- refresh the Live Activity during inactive/background/foreground scene transitions;
- attach a monotonically changing presentation revision so state-equivalent refreshes are still distinct ActivityKit content updates.

This mirrors the system refresh that previously occurred only after repeated lock/unlock transitions. SpringBoard still owns final Dynamic Island arbitration, so a device test is required and absolute suppression of the media pill cannot be guaranteed through public iOS 18.5 APIs.

## Dynamic Island layout

Compact RX/TX indicators now have explicit 20 pt containers with 16 pt symbols. The trailing microphone gets extra right-side breathing room so `mic.slash.fill` does not touch the compact-region clipping boundary. Expanded TX also reserves an explicit symbol frame.

## Automatic jitter

The 3.3.0 adaptive RX jitter controller is retained unchanged: 20 ms floor, measured packet-arrival variation, immediate safety increase after underflow, and gradual reduction after stable playback.

## Validation performed in this package

- Swift syntax parse on every `.swift` source file
- YAML parse for `project.yml` and GitHub Actions workflow
- JSON parse for asset catalog files
- plist validation for entitlements
- ZIP integrity test after packaging

A true semantic iOS build and Dynamic Island/Lock Screen behavior test still require Xcode 16.4 with the iOS 18.5 SDK and a signed physical iPhone.

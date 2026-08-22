# MisMeeter 4.0.4

MisMeeter is a native iOS 18.5 app for real-time VBAN audio transmission and reception over a local network, with Live Activity, Dynamic Island, WidgetKit and native iOS 18 Controls.

## Main features

- VBAN microphone transmission at 48 kHz / PCM16
- VBAN mono/stereo reception with adaptive jitter buffering
- Independent TX microphone mute and RX playback mute
- VoiceProcessingIO or raw RemoteIO capture
- Live Activity and Dynamic Island status/actions
- Home Screen / Lock Screen widget
- Native iOS 18 Control Center / Lock Screen controls
- Shared App Group state with atomic file publication
- Background audio mode
- External-route-safe audio policy: built-in speaker is preferred only when iOS falls back to the receiver; external routes are not forcibly overridden

## Build target

- Xcode 16.4
- iOS SDK 18.5
- Minimum iOS 18.5
- App version 4.0.4 (build 104)
- Project generation: XcodeGen

Generate the Xcode project with:

```bash
xcodegen generate
```

Then open `MisMeeter.xcodeproj` or build the `MisMeeter` scheme.

## Validation

Run the repository audit with:

```bash
bash Scripts/validate-package.sh
```

The script parses every Swift source, validates JSON/plist resources, checks explicit XcodeGen source membership, verifies App Group/release identity, and asserts the critical Control Center, runtime, audio and network invariants introduced by the 4.0.4 senior review.

The included GitHub Actions workflow additionally generates a clean project on macOS 15 with Xcode 16.4, performs an unsigned Release build against iOS 18.5, rejects Swift compiler warnings, checks final build products, and packages an unsigned IPA artifact.

## Architecture notes

The app/runtime is the authoritative owner of transport state. WidgetKit Controls, widgets and Live Activity derive presentation state from the same normalized App Group snapshot. Control Center mute actions use `SetValueIntent + LiveActivityIntent`; app-originated changes explicitly invalidate configured controls, while an interacted Control relies on WidgetKit's automatic post-intent refresh.

TX is clocked directly by the Core Audio input callback and uses a connected nonblocking UDP socket. RX uses a serial UDP receive queue, monotonic VBAN frame validation, a bounded jitter buffer, and low-rate clock correction for independent sender/device clocks. Diagnostics are sampled outside the realtime audio callback.

See `SENIOR-IOS-REVIEW-4.0.4.md` for the complete review and the changes applied.

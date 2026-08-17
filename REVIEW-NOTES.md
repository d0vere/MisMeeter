# MisMeeter 3.2.6 — iOS 18.5 UI / Duplex Live Activity

- Deployment target moved to iOS 18.5; custom cards/navigation use an iOS 18.5-compatible ultra-thin Material treatment.
- Dynamic Island compact mode is symmetric: RX speaker at compact-leading, TX microphone at compact-trailing. Red indicates that channel is muted, green indicates active audio.
- Expanded Live Activity title is intentionally only “Live” and exposes three large controls: RX mute, microphone mute, Stop All.
- RX mute keeps the network receiver, jitter buffer, clock recovery and AVAudioEngine running; only playback output is attenuated to zero.
- Live Activity lifecycle is duplex-aware: either TX or RX can create/keep it alive; it ends only when both stop or Stop All is invoked.
- Widget controls mirror the same three actions.
- Main navigation is swipeable using a page-style TabView plus a narrower translucent floating selector. The Home settings shortcut was removed.

> iOS applications must not terminate themselves programmatically. Stop All stops both audio paths and ends the Live Activity; it intentionally does not call `exit(0)`.

---

# Senior iOS review notes — MisMeeter 3.1.0

## Root cause addressed
The previous lock-screen mitigation focused on a secondary TX scheduling thread. The capture callback already had diagnostics showing that microphone delivery could remain regular while the TX worker experienced wake gaps. The old worker then intentionally trimmed stale PCM and resumed near-live audio, which protects latency but creates missing audio at the destination.

The 3.0 transmitter removes that scheduler boundary. Each 48 kHz Core Audio callback is converted in preallocated memory and packetized directly into 256-sample VBAN datagrams. The UDP descriptor is connected and nonblocking, so the audio callback never waits for a GCD queue or network dispatch queue.

## Additional correctness fixes
- UDP socket creation is synchronous and throws before capture starts.
- Invalid/hostname destinations no longer leave a microphone session running with a not-yet-ready socket.
- No per-packet Swift Array creation remains in the TX realtime path.
- Old capture/TX queue implementations and the Audio Workgroup C bridge were removed.
- Main app and Widget Extension share state through an App Group.
- Widget/Live Activity Mute and Stop actions signal the already-running app process through a Darwin notification instead of relying on a separate extension singleton.
- Live Activity content includes duplex state, destination, preset and session start time.
- A regular WidgetKit widget was added for Home Screen and Lock Screen families.

## Validation performed in this environment
- All Swift files: `swiftc -parse` successful.
- `project.yml`: YAML parse successful.
- GitHub Actions workflow: YAML parse successful.
- AppIcon asset catalog JSON: JSON parse successful.
- App icon size/source manually inspected.
- Old TX worker/workgroup references removed.

A full iOS SDK semantic build cannot run in this Linux environment. GitHub Actions is configured to perform that build using `macos-15` and requires Xcode 16.4 exactly or newer compatible toolchain.

## Device test checklist
1. Sign both targets with App Group `group.dev.mismeeter.app` enabled.
2. Start TX to a fixed LAN IPv4 destination and verify continuous audio foreground.
3. Lock iPhone for at least 10 minutes while measuring receiver packet cadence and listening for gaps.
4. Repeat with VoiceProcessingIO and Raw RemoteIO.
5. Exercise Mute/Unmute and Stop from Dynamic Island, Lock Screen Live Activity and Home Screen widget.
6. Run TX + RX simultaneously and verify speaker route remains stable.
7. Test interruption recovery for calls/Siri and Wi-Fi route changes before production release.

## 3.1.0 UX/state pass

- Dynamic Island compact presentation now renders only a small microphone glyph on the right side: green while live, red while muted. Expanded controls remain available on deliberate expansion.
- Lock Screen Live Activity is slimmer and retains Mute/Stop controls.
- External Stop immediately clears the shared transport snapshot and foreground activation reconciles runtime/shared state to prevent stale Mute/Stop UI.
- Root navigation is now a custom floating material capsule instead of the fixed TabView bar; it hides while editing preset text fields.
- Navigation order is Home (TX), Receive (RX Home), Presets, Settings.
- The former Monitor screen is integrated into Settings as Transport, Core Audio and Receiver diagnostic sections.
- Small and medium widgets expose both Mute and Stop while TX is active.

## 3.2.6 CI build fix

- GitHub Actions targets `macos-15` and explicitly selects `/Applications/Xcode_16.4.app/Contents/Developer`.
- The workflow verifies the selected iPhoneOS SDK is exactly 18.5 before project generation.
- Deployment target is iOS 18.5 for both the app and Widget extension.
- Xcode 16.4 compatibility uses a lightweight ultra-thin Material treatment instead of the unavailable iOS 26 `glassEffect` API.
- App and widget versions are 3.2.6 (build 36).
- CI artifact is now `MisMeeter-3.2.6-unsigned.ipa`.

## 3.2.6 Send / Widget refinement
- Renamed the TX root tab and navigation title from Home/MisMeeter to **Send**.
- Moved **Input gain** and **Capture engine** from Settings into a dedicated Send controls card. Capture engine remains locked while TX is live; gain remains live-adjustable.
- Replaced the Send screen's System Surfaces card with **Send quality** diagnostics: packets sent, send errors, max TX gap, capture rate and TX rate.
- Pulled the expanded Dynamic Island leading/trailing content inward to avoid clipping against the island mask.
- Widget hierarchy now leads with the active preset name and current transport state instead of generic Live copy.
- Runtime now remembers the active RX preset so RX-only widgets show the correct Receive preset rather than a stale TX preset.
- Version bumped to 3.2.6 (build 36); Xcode 16.4 / iOS 18.5 CI remains unchanged apart from artifact versioning.

## 3.2.6 Dynamic Island / Widget separation

- Send page order is now Hero → Level → TX/RX status → Send Controls → Send Quality.
- Expanded Dynamic Island aligns RX to the inner edge of the leading region and TX to the inner edge of the trailing region so the indicators stay visually attached to the compact notch anchors.
- The Home Screen Widget no longer mirrors the Live Activity. Small and Medium families use a dedicated Send/Receive dashboard with preset, independent transport state and controls.
- Accessory widgets remain intentionally concise for Lock Screen legibility.
- Version is 3.2.6 (build 36); Xcode 16.4 / iOS 18.5 CI remains the build baseline.


## 3.2.6
- Separate `sendPresetName` and `receivePresetName` added to the shared snapshot with backward-compatible decoding.
- Dynamic Island expanded header is split around the camera: RX preset + speaker on the left, microphone + TX preset on the right; generic Live label removed.
- Dedicated Widget dashboard now uses TX/RX preset rows and no Live/Duplex Live heading.
- Mute controls use green when the corresponding path is active/unmuted and red when muted. Stop All stays red.


## 3.2.6 Island label + Widget single-row refinement

- Dynamic Island expanded preset labels now sit immediately after their RX/TX indicators with no spacer or outer padding.
- Home Screen widget uses one status row: `RX - preset   TX - preset`, with RX/TX icons grouped at the far right.
- Three transport controls remain on the bottom row; RX/TX buttons continue to reflect green active / red muted state, Stop All remains red.
- Build baseline remains Xcode 16.4 + iOS 18.5.

# MisMeeter 4.0.4 — Senior iOS Code Review

Version: **4.0.4 (build 104)**
Deployment target: **iOS 18.5**
Reference toolchain: **Xcode 16.4 / iOS SDK 18.5**

## Executive summary

The project was reviewed end-to-end across SwiftUI state, transport lifecycle, Core Audio, UDP/VBAN framing, adaptive RX buffering, App Group persistence, ActivityKit, WidgetKit Controls, target membership and CI/package validation.

The review deliberately preserves the existing visual hierarchy, navigation, controls, VBAN format, 48 kHz audio contract, mute semantics, preset model and iOS system surfaces. Changes focus on correctness, realtime safety, race reduction, failure cleanup and removal of dead architecture.

No known source-level blocker remains after the included static validation. A true Apple-platform compile/link/runtime certification still requires the included Xcode 16.4 CI workflow or a local Mac because the review environment does not provide `xcodebuild` or Apple SDK runtime testing.

## High-priority defects fixed

### 1. Unsafe UDP port conversion

The UI previously used `UInt16(Int(text) ?? 6980)`. A numeric value outside `UInt16` range could trap at runtime instead of failing validation.

**Fix:** TX and RX now validate the selected port explicitly as `1...65535` before startup and present the existing app alert flow for invalid values. Runtime RX also rejects port `0` defensively.

### 2. Microphone permission was not explicitly gated

TX could proceed to capture setup without an explicit permission decision, which can produce unusable capture behavior when recording access is denied.

**Fix:** TX startup now awaits `AVAudioApplication.requestRecordPermission()` and aborts cleanly with a user-visible message if access is denied.

### 3. Realtime callback performed non-realtime work

The microphone render callback previously emitted UI/diagnostic callbacks and queried `AVAudioSession` periodically from the realtime path. Queue dispatch/framework calls can block or allocate at exactly the point where audio deadlines must be deterministic.

**Fix:** the callback now renders, converts and sends only. It updates a small locked diagnostics snapshot; a low-priority timer publishes meter/timing data and queries `AVAudioSession` outside the realtime callback.

### 4. Hardware sample-rate assumption could reject valid routes

Capture previously hard-failed when the hardware route did not report exactly 48 kHz even though RemoteIO/VoiceProcessingIO can bridge application and hardware formats.

**Fix:** the application-side format remains fixed at the required VBAN 48 kHz, while the Audio Unit is allowed to perform route conversion. `MaximumFramesPerSlice` is explicitly bounded to the preallocated 8192-frame realtime buffers.

### 5. RX duplicate/out-of-order sequence handling could corrupt loss metrics and audio

The previous frame-tracking path could advance accounting incorrectly for duplicate or stale datagrams, leading to false packet-loss values and stale PCM entering the playback buffer.

**Fix:** RX now uses wrap-safe UInt32 monotonic sequence arithmetic, rejects duplicates/out-of-order frames before decoding/push, and counts bounded forward gaps only. Arrival-jitter baselines are updated only for valid forward packets.

### 6. TX sequence number hid local UDP drops

The transmitter advanced the VBAN frame counter only after a successful `send()`. A local nonblocking socket drop could therefore disappear from the receiver's sequence gap.

**Fix:** the VBAN frame counter advances for every generated packet. Local send failures remain counted in TX diagnostics and now also create the correct observable frame gap.

### 7. RX socket close could race an in-flight `recv()`

The socket descriptor could be closed outside the receive queue immediately after canceling its dispatch source, allowing a handler already running on the queue to race close/file-descriptor reuse.

**Fix:** dispatch-source cancellation and descriptor close are serialized on the RX network queue. The control timer is likewise drained on its own queue before graph teardown.

### 8. RX startup failure cleanup was incomplete

A failure after partial AVAudioEngine/AVAudioSession setup could leave nodes/session state active even though runtime state reported RX stopped.

**Fix:** runtime failure handling now calls the receiver's full rollback path and deactivates the session only when TX is not using it.

### 9. Audio-session operations were not globally serialized

TX, RX, route notifications and recovery paths could issue `AVAudioSession` mutations from different queues.

**Fix:** `AudioSessionCoordinator` serializes category, timing, activation/deactivation and speaker policy. Route recovery reasserts preferred timing even if the category itself is unchanged.

### 10. Speaker override could interfere with external routes

The old force-speaker path could override routing policy more broadly than required.

**Fix:** `.defaultToSpeaker` remains the normal duplex policy, but explicit override occurs only when the current output is actually the built-in receiver. Bluetooth, CarPlay, AirPlay, USB and headphones are not forcibly replaced.

### 11. Runtime status callbacks had multiple competing sources of truth

Lower-level TX/RX callbacks published user-visible runtime status during teardown. This could overwrite a newer authoritative `Ready`/duplex state after `stopAll()` or partial stop transitions.

**Fix:** transport state is now derived from one synchronized runtime snapshot. Lower layers publish diagnostics only; SwiftUI and system surfaces reconcile from authoritative runtime state.

### 12. Live Activity operations could race start/stop and duplicate activities

Independent asynchronous ActivityKit calls could overlap, especially when TX/RX were started or stopped in quick succession.

**Fix:** ActivityKit ownership is centralized in an actor. Updates carry a monotonically increasing presentation revision; stale reconcile requests are ignored, duplicate activities are ended, and RX-only sessions use the RX stream identity rather than an unrelated TX preset.

### 13. UI could show edited preset values instead of the active transport

Preset text fields remain editable while a transport is active. The home hero previously displayed the currently edited AppStorage preset, which could diverge from the preset actually used by the running socket.

**Fix:** active TX/RX screens display the runtime's active preset; when stopped they display the editable selected preset. Editing behavior and layout are otherwise unchanged.

### 14. Stale/incorrect app version in Settings

The About section displayed `3.2.3` in a 4.0.4 project.

**Fix:** the version is read from `CFBundleShortVersionString`, with a 4.0.4 fallback.

## Dead/obsolete code removed

- `Shared/VBANTransmissionMode.swift`
- `Shared/TransportState.swift`
- unused `transmissionModeV08` AppStorage path
- obsolete scene-phase transport diagnostic hooks
- unused `VBANPacket.make(...)`
- unused VBAN channel constant
- unused runtime direct-set mute wrappers superseded by toggle/system-control entry points
- unused receive-only AudioSession wrapper
- redundant lower-layer status/transport diagnostic callbacks
- obsolete review-note document superseded by this report

`project.yml` keeps explicit source membership, so deleted/legacy Swift files cannot silently re-enter the build through recursive directory inclusion.

## Additional hardening and optimization

- Reusable RX datagram buffer instead of allocating a new packet buffer per wake.
- RX dispatch-source drain is capped per wake to preserve queue fairness under burst traffic.
- VBAN RX validates the audio protocol bits and exact PCM16 format before decoding.
- Stream names are restricted to printable ASCII and 16 VBAN bytes with existing fallback names.
- Shared App Group snapshot writes are serialized, normalized and logged on persistence failure.
- Widget timelines continue to derive from the single atomic shared snapshot; no second UserDefaults state cache was introduced.
- Control Center kinds remain stable to preserve existing user placements.
- Invalid persisted preset indices/capture mode values are normalized on UI appearance.
- Voice-processing diagnostics report `Idle` when TX is stopped instead of presenting stale engine state.
- GitHub CI now executes the package audit before project generation/build.
- The package audit no longer depends on PyYAML; its local checks use Python standard-library parsing plus XcodeGen's YAML validation in CI.

## Control Center review

The iOS 18 Controls retain the correct stateful model:

- `ControlWidgetToggle`
- `ControlValueProvider`
- shared `SharedAppState` snapshot
- `SetValueIntent + LiveActivityIntent`
- no `.disabled(...)` on the system Control template
- no manual ControlCenter reload from inside an interacted intent
- explicit exact-kind invalidation for app-originated state changes
- stable v4 `kind` identifiers

The runtime remains authoritative: an idle control can deliver its intent, but the runtime refuses to apply a mute state to an inactive transport and republishes the authoritative snapshot.

## Realtime/audio review

TX remains audio-clocked with no timer/semaphore packet pacer between Core Audio and UDP. The packetization buffer and conversion scratch storage are preallocated. The socket is connected and nonblocking. Diagnostics never query AVAudioSession from the audio render callback.

RX retains adaptive jitter control and TimePitch clock correction. Network parsing, packet counters and sequence accounting remain on the serial RX queue; audio graph recovery is serialized on the receiver control queue. The ring buffer remains bounded and discards oldest audio rather than allowing unbounded latency growth.

## Validation performed in this package

The included `Scripts/validate-package.sh` currently passes and checks:

- Swift syntax parse for every source file
- exact explicit Swift source membership in `project.yml`
- JSON and entitlement plist parsing
- App Group identity parity
- app version/build identity
- system Control architectural invariants
- absence of the removed legacy transport files/settings
- safe port-conversion invariant
- explicit microphone permission gating
- Audio Unit maximum-frame bound
- RX monotonic frame acceptance and serialized socket teardown

Additional review-host checks performed before packaging:

- `git diff --check`
- project-wide searches for removed callbacks/legacy symbols
- project-wide search for force-cast/`try!`/fatal-error style hazards
- individual Swift syntax parsing after every major refactor

## macOS/Xcode CI gate

`.github/workflows/build-ios.yml` is the definitive Apple-toolchain gate. On macOS 15 it:

1. selects Xcode 16.4 and verifies iOS SDK 18.5;
2. installs XcodeGen;
3. runs `Scripts/validate-package.sh`;
4. generates a clean Xcode project;
5. verifies target/source architecture;
6. lints generated plists/entitlements;
7. performs an unsigned Release iPhoneOS build;
8. fails on Swift compiler warnings;
9. validates app + widget build products and legacy-symbol absence;
10. packages an unsigned IPA artifact.

## Residual verification scope

No source review can truthfully guarantee “bug-free” behavior on every iPhone/audio route/network without running the Apple binary. Before production release, the recommended acceptance matrix is:

- physical iPhone on speaker, wired/USB and relevant Bluetooth/CarPlay routes;
- microphone permission: first prompt, denied, later re-enabled;
- TX-only, RX-only and duplex transitions in both orders;
- lock screen/background/foreground/interruption/route changes;
- rapid start/stop/mute sequences from app, Dynamic Island, widget and Control Center;
- VBAN sender packet loss, duplicates, out-of-order packets and UInt32 frame wrap;
- long-duration drift/jitter run;
- Xcode 16.4 Release build with zero Swift warnings.

The packaged code is configured so that the CI build performs the compile-time portion of that matrix automatically.

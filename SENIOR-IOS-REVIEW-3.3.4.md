# MisMeeter 3.3.4 — Senior iOS review

## Architecture

- **ActivityKit** is the only Live Activity / Dynamic Island presentation layer.
- **WidgetKit Controls** provide exactly two locked-device controls: Mic and RX.
- **App Intents** request exact final states with `.alwaysAllowed` and `openAppWhenRun = false`.
- **App Group + Darwin notification** bridge Control requests to the already-running audio runtime.
- **SharedTransportSnapshot is output-only**: UI extensions no longer mutate it optimistically or reconcile it back into the runtime.

## Fixes after the 3.3.3 CI failure

The failing repository still contained old files that were automatically included because XcodeGen previously used recursive directory sources. 3.3.4 now enumerates every source file explicitly for both app and widget targets and regenerates `MisMeeter.xcodeproj` from scratch in CI.

Legacy implementations such as `NowPlayingRemoteController.swift`, `TXPacketQueue.swift`, `CaptureRingBuffer.swift`, `AudioClockEstimator.swift`, `MonotonicPacer.swift`, `SampleFIFO.swift`, and `mismeeter-silence.wav` cannot enter the generated target even if an old checkout still contains them.

CI also checks the generated project and final app binary for removed Now Playing/media symbols.

## Native Controls

Mic and RX use `ControlWidgetToggle` + `ControlValueProvider` + `SetValueIntent`.

- The provider reads the latest runtime-owned App Group snapshot.
- The intent sends an exact requested value, never a blind toggle.
- The runtime applies the command and republishes the authoritative snapshot.
- WidgetKit automatically reloads the invoking Control after `perform()` returns; app-side state changes request targeted `ControlCenter` reloads.
- Controls are disabled while their transport is inactive.

The former third Stop All system Control was removed to keep the requested two-Control surface. Stop All remains available in the Live Activity interface.

## Command transport hardening

3.3.4 replaces the single shared command slot with independent mailboxes for Mic, RX, and Stop All. Rapid interactions on different controls can no longer overwrite each other before the runtime consumes them. Stop All dominates a simultaneous command burst.

## Runtime state ordering

TX/RX stop paths now publish the intended stopped state before lower-level callbacks can emit status messages. This avoids transient snapshots such as `isStreaming == true` paired with a `Stopped` status.

## Dynamic Island

Compact mode places both RX and TX in `compactLeading`; `compactTrailing` is empty. Inactive channels stay dimmed instead of changing the compact footprint.

## Automatic RX jitter

The adaptive jitter controller remains automatic: it starts near 35 ms, reacts quickly to underflow/network variation, and gradually converges toward a measured-safe low-latency floor (20 ms minimum, 250 ms safety ceiling).

## Validation performed in this package

- Swift parser validation across every source file using Swift 6.2 parser
- source-manifest validation against `project.yml`
- YAML validation for XcodeGen and GitHub Actions
- JSON asset validation
- plist/entitlement parsing
- stale implementation/resource scan
- package ZIP integrity validation

A true Apple SDK type-check/build still requires Xcode 16.4 on macOS. The included GitHub Actions workflow performs that Release `iphoneos18.5` build and rejects legacy source membership before compilation.

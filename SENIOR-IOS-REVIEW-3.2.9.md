# MisMeeter 3.2.9 — Senior iOS review

## Main changes
- Added three iOS 18 WidgetKit `ControlWidget` actions: Receive mute, Microphone mute, Stop All.
- Explicit `IntentAuthenticationPolicy.alwaysAllowed` on all three action intents.
- Kept `openAppWhenRun = false` so actions remain extension/system driven.
- Preserved the App Group + Darwin notification bridge to the already-running audio runtime.
- Updated app/widget marketing version to 3.2.9 and build to 40.
- Updated CI artifact names to 3.2.9.

## Locked-device behavior
Apple intentionally prevents ordinary WidgetKit widget and Live Activity buttons/toggles from executing on a locked device until authentication. This cannot be bypassed by application code. The supported iOS 18 action surface is a WidgetKit Control (`ControlWidget`) placed in Control Center or the Lock Screen controls area. The supplied intents are explicitly configured as `alwaysAllowed`, which permits the intent itself to run without requesting authentication when the system surface permits locked-device execution.

Primary Apple references:
- https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system
- https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy

## Validation performed
- `swiftc -parse` across all Swift source files: PASS.
- `project.yml` YAML parse: PASS.
- Asset JSON parse: PASS.
- App Group entitlements present in both app and widget extension.
- Deployment target remains iOS 18.5 / Xcode 16.4 baseline.

## Validation that still requires macOS/Xcode/device
A Linux review environment cannot run an iOS SDK semantic build, code signing, ActivityKit runtime, AVAudioSession, or a physical locked-device interaction test. Run the existing GitHub Actions Xcode 16.4 build and then test the three Controls on a signed iPhone. No responsible review can guarantee “bug-free” software without those runtime/device tests.

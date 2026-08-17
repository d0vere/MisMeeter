# MisMeeter 3.2.6 — Audio-clocked VBAN for iOS
## 3.2.6 system surfaces refinement

- Dynamic Island expanded mode no longer shows generic “Live” text. RX and TX each show their own active preset around the physical camera area.
- Shared transport state now carries independent Send and Receive preset names for WidgetKit and ActivityKit.
- Widget UI is independent from the Live Activity and shows `TX · preset` / `RX · preset` with status icons aligned on the opposite side.
- RX/TX action buttons mirror transport state colors: green while active, red while muted; Stop All remains red.
- Expanded Island indicators are inset away from the camera/sensor cutout to avoid physical occlusion.


## 3.2.6 interface refinement

- Send status tiles (TX/RX) are positioned above Send Controls.
- Expanded Dynamic Island keeps the RX speaker and TX microphone anchored toward the sensor, matching their compact visual positions.
- Home Screen Widget is now a dedicated Send/Receive dashboard instead of mirroring the Live Activity.
- Widget shows preset, independent RX/TX state and quick controls; Lock Screen accessory widgets remain deliberately compact.
- Xcode 16.4 / iOS 18.5 compatibility is unchanged.

## What changed in 3.0

### Lock-screen TX fix
The critical microphone-to-network path was rebuilt.

Previous releases inserted a high-priority GCD worker, semaphore wakeups and an elastic queue between the Core Audio callback and UDP. On a locked iPhone, the microphone callback could remain healthy while the auxiliary worker woke late. That produced packet gaps, queue trimming and audible stutter on the destination.

3.0 uses the Core Audio input callback itself as the transmission clock:

`RemoteIO / VoiceProcessingIO -> preallocated PCM conversion -> connected nonblocking UDP -> VBAN`

Properties of the new TX path:
- no timer
- no DispatchQueue worker
- no semaphore
- no catch-up burst
- no stale PCM queue
- no allocation per packet
- synchronous socket validation before capture starts
- connected IPv4 UDP socket with a large send buffer and `O_NONBLOCK`
- 48 kHz / mono / Int16 / 256 samples per VBAN packet

The app keeps `UIBackgroundModes = audio` and an active `.playAndRecord` audio session while TX/RX requires it.

### UI / UX rebuild
The app UI was rebuilt around four system-native areas:
- **Home** — transmission state, level meter, mute, start/stop and live-surface status
- **Receive** — a dedicated RX Home with listening state, receive buffer and quality metrics
- **Presets** — three TX and three RX presets with dedicated editors
- **Settings** — capture/background controls, gain and integrated Core Audio/VBAN/RX diagnostics monitor

The project is compiled with Xcode 16.4 and the iOS 18.5 SDK. The custom floating navigation and cards use a lightweight ultra-thin Material treatment with subtle borders and shadows, preserving the modern translucent direction without relying on iOS 26-only APIs.

### Duplex Live Activity + Dynamic Island + Widget
These remain first-class system surfaces in 3.2.6 on iOS 18.5:
- Lock Screen Live Activity with large RX mute, microphone mute and Stop All controls
- compact Dynamic Island with RX speaker on the left and TX microphone on the right
- RX-only and TX-only Live Activity lifecycle support
- Home Screen small and medium widget with the same three controls
- Lock Screen accessory circular and rectangular widget
- shared session state through App Group `group.dev.mismeeter.app`
- Darwin notification control bridge to the running audio process

For a signed device build, enable the App Group `group.dev.mismeeter.app` for both the main app and the Widget Extension in the Apple Developer portal/provisioning profiles.

### App icon
A new waveform/glass app icon is included in `MisMeeter/Assets.xcassets/AppIcon.appiconset` together with a 1024px source image.

## GitHub Actions
`.github/workflows/build-ios.yml` now:
- uses `macos-15`
- explicitly selects Xcode 16.4 and verifies the iOS 18.5 SDK
- installs XcodeGen
- regenerates the Xcode project
- validates generated plists and entitlements
- builds the app and Widget Extension for generic iOS device with signing disabled
- packages `MisMeeter-3.2.6-unsigned.ipa`
- uploads the IPA and failure logs

## Local generation

```bash
brew install xcodegen
xcodegen generate
open MisMeeter.xcodeproj
```

## Device signing note
The GitHub artifact is intentionally unsigned. For an installable device/App Store build, configure a Development/Distribution team and provisioning profiles that contain the App Group capability for both targets.

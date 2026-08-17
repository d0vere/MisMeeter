# MisMeeter 3.2.0 — Audio-clocked VBAN for iOS

MisMeeter streams the iPhone microphone to a VBAN/VoiceMeeter destination and can independently receive a VBAN stream back to the iPhone.

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

The project is compiled with the iOS 26 SDK / Xcode 26.6 so standard navigation, tabs, sheets and controls adopt Apple’s current Liquid Glass design language while keeping iOS 26.6 as the deployment target.

### Duplex Live Activity + Dynamic Island + Widget
These are first-class iOS 26.6 surfaces in 3.2:
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
- uses `macos-26`
- checks that Xcode 26.6 or newer is selected
- installs XcodeGen
- regenerates the Xcode project
- validates generated plists and entitlements
- builds the app and Widget Extension for generic iOS device with signing disabled
- packages `MisMeeter-3.2.0-unsigned.ipa`
- uploads the IPA and failure logs

## Local generation

```bash
brew install xcodegen
xcodegen generate
open MisMeeter.xcodeproj
```

## Device signing note
The GitHub artifact is intentionally unsigned. For an installable device/App Store build, configure a Development/Distribution team and provisioning profiles that contain the App Group capability for both targets.

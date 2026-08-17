# Senior iOS review notes — MisMeeter 3.0.0

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

A full iOS SDK semantic build cannot run in this Linux environment. GitHub Actions is configured to perform that build using `macos-26` and requires Xcode 26.6+.

## Device test checklist
1. Sign both targets with App Group `group.dev.mismeeter.app` enabled.
2. Start TX to a fixed LAN IPv4 destination and verify continuous audio foreground.
3. Lock iPhone for at least 10 minutes while measuring receiver packet cadence and listening for gaps.
4. Repeat with VoiceProcessingIO and Raw RemoteIO.
5. Exercise Mute/Unmute and Stop from Dynamic Island, Lock Screen Live Activity and Home Screen widget.
6. Run TX + RX simultaneously and verify speaker route remains stable.
7. Test interruption recovery for calls/Siri and Wi-Fi route changes before production release.

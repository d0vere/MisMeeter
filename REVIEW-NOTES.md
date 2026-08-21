# MisMeeter 3.3.5 — RX speaker recovery + clearer native Controls


- Fixed RX receiving packets with silent device output: RX-only now uses `AVAudioSession.Category.playback`; duplex uses `playAndRecord`.
- Added receiver recovery for route changes, audio-session interruptions, and `AVAudioEngineConfigurationChange`.
- Receiver validates that a hardware output format exists before starting and reasserts the session when TX starts/stops while RX remains active.
- Changed Control Center visuals to a stable green ON tint plus explicit filled/slashed symbols and `TX ON / TX MUTED` / `RX ON / RX MUTED` status text.
- Fixed the root cause of the 3.3.3 CI regression: XcodeGen no longer recursively includes whole source directories.
- App and Widget source membership is now explicit and reproducible.
- CI regenerates the Xcode project from scratch and rejects all known legacy Now Playing / old TX sources.
- Removed the third Stop All system Control; Control Center / Lock Screen expose only Mic and RX as requested.
- Mic/RX Controls remain exact-value, stateful, `.alwaysAllowed`, runtime-authoritative toggles.
- Replaced the single control-command slot with independent Mic / RX / Stop All mailboxes.
- Removed snapshot-to-runtime reconciliation; the shared snapshot is output-only truth from the audio runtime.
- Hardened stop-state ordering to avoid transient stale transport snapshots.
- Fixed the current `MicrophoneEngine` immutable-buffer compiler warning.
- Dynamic Island remains ActivityKit-only with RX + TX together in compact leading and no compact trailing content.
- Automatic adaptive RX jitter remains enabled.
- Version 3.3.5, build 47.

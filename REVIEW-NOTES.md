# MisMeeter 3.3.4 — Build hygiene + native Control hardening

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
- Version 3.3.4, build 46.

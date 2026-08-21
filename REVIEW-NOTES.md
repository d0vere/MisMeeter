# MisMeeter 3.3.7 review notes

- Fixed Control Center controls stuck grey/IDLE after transport startup.
- Removed the premature `reloadAllControls()` from `App.init`.
- Shared transport snapshot now uses an atomic JSON file in the App Group container, with UserDefaults only as fallback.
- Control command mailboxes now use atomic per-action App Group files before posting the Darwin notification.
- TX/RX Control Center actions use dedicated plain `AppIntent` implementations instead of the Live Activity intents.
- Controls are never disabled from a potentially cached provider value; idle taps are safely ignored by the intent after an authoritative state check.
- Visual state remains: green normal symbol = active, red slashed symbol = muted, neutral = idle.
- Live Activity / Dynamic Island behavior and the 3.3.5 RX speaker fixes are unchanged.

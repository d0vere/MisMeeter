# MisMeeter 3.3.7 — Control Center reliability review

## Fixed

- Replaced cross-process transport-state reads with an atomic App Group JSON snapshot.
- Replaced UserDefaults-only control mailboxes with atomic per-action App Group mailbox files plus Darwin notification.
- Control Center buttons no longer become permanently disabled from a stale IDLE render.
- Added dedicated `AppIntent` actions for Control Center instead of reusing `LiveActivityIntent`.
- TX renders green with `mic.fill` while active, red with `mic.slash.fill` while muted.
- RX renders green with `speaker.wave.3.fill` while active, red with `speaker.slash.fill` while muted.
- IDLE remains neutral; tapping an idle control safely performs no action.
- Existing Live Activity intents and Dynamic Island behavior remain separate and unchanged.

## Cross-process ordering

The app writes the authoritative snapshot atomically to the App Group container before asking WidgetKit to reload a control. Control commands are likewise atomically committed before the Darwin wake-up is posted. This removes the previous preference-cache race.

- Shared files use complete-until-first-authentication data protection so they remain accessible after the first device unlock, including subsequent locked-screen control use.

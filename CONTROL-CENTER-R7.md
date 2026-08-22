# MisMeeter 4.0.4 — Control Center R7 / build 110

R6 device testing proved both app-originated and Control-originated state changes can leave the displayed control on the old value, even though the underlying audio state changes correctly. R6 already avoids manual reloads on the SetValueIntent path and uses an atomic App Group state file, so R7 does not change those paths again.

R7 intentionally changes the Control `kind` identifiers from v4 to v5. A Control kind is its system identity and is also the exact identifier passed to `ControlCenter.reloadControls(ofKind:)`. Reusing the same v4 identity across the earlier experimental builds allowed existing Control Center placements/templates to survive all those implementation changes. This build forces iOS to create fresh controls and gives the reload API a fresh matching identity.

TX/RX visible titles now also follow the provider Bool (`ACTIVE` / `MUTED`) for device diagnostics.

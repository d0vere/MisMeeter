# MisMeeter 4.0.4 — Control Center R4 / build 107

R4 removes the remaining false-state path rather than adding another lifecycle workaround.

- Control providers now expose the exact Boolean mute value; transport activity is no longer mixed into the toggle value.
- A failed App Group snapshot read is treated as unavailable and throws from `currentValue()` instead of fabricating `.idle` / `false`. Apple explicitly allows `currentValue()` to throw when state cannot be computed.
- App launch/background no longer forces broad `reloadAllControls()` calls. Runtime changes use targeted reloads and iOS reloads an interacted Control after its intent returns.
- Each SetValueIntent verifies that the persisted mute value equals the requested value before returning success.
- Build 107.

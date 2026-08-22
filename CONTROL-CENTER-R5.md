# MisMeeter 4.0.4 — Control Center R5 / build 108

R5 is based on the visually stable R3 and changes only Control Center state synchronization.

- The provider is always renderable and returns a plain Bool, matching Apple's ControlWidgetToggle pattern.
- TX/RX mute each have a tiny App Group UserDefaults shadow value, independent of the full transport JSON snapshot.
- A SetValueIntent commits the requested value before applying it to the runtime.
- Runtime-originated mute changes update the same shadow value.
- The full snapshot remains the fallback for first use and continues to carry session metadata.

This targets the observed stale re-render/double-tap cycle without the R4 throwing-provider regression.

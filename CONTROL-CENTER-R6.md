# Control Center R6 — build 109

R6 keeps the R5 visual behavior but replaces the App Group UserDefaults mute shadow with a dedicated atomic file. The app and WidgetKit are separate processes; a process-local CFPreferences cache can keep returning the previous Boolean even after the real runtime changed. The provider now performs a fresh file read every evaluation. App-originated changes still write before targeted Control Center invalidation; intent-originated changes write before returning.

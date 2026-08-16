# MisMeeter v1.0 — Background Stable VBAN

## Background / Lock Screen transport

The Core Audio side from v0.9 is retained:

iPhone microphone
-> optional Apple Voice Processing
-> AVAudioSinkNode realtime callback
-> PCM16
-> VBAN

The remaining issue was network delivery while the app was backgrounded / the screen was locked.

v1.0 uses SwiftUI scenePhase to switch the network transport automatically.

### Foreground Realtime

- 1 VBAN frame = 256 samples
- send immediately
- ~5.33 ms packet cadence
- minimum sender-side latency

### Background Stable

- collect 4 VBAN frames
- 1024 samples total
- ~21.33 ms worth of audio
- send the 4 UDP datagrams consecutively from the same serial-queue execution window

This reduces dependency on the frequency at which iOS schedules ordinary networking work while
the screen is locked. The Core Audio capture callback itself remains realtime.

## Diagnostics

Status shows:

- App transport: Foreground Realtime / Background Stable
- VBAN batch: 1 or 4 packets
- Batch buffer: queued samples
- Input callback
- Actual I/O buffer
- Capture rate
- TX rate
- Underruns

## Apple Voice Processing

Retained from v0.9.

When enabled, MisMeeter uses Apple's VoiceProcessingIO path for speech-oriented processing such as
noise suppression, automatic voice gain processing and acoustic echo cancellation.

## Existing features retained

- 3 VBAN presets
- software gain slider
- Live Activity / Dynamic Island mute
- background audio
- direct VBAN UDP to VoiceMeeter
- 48 kHz PCM16 mono

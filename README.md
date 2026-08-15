# MisMeeter v0.3

iPhone microphone -> VBAN -> VoiceMeeter, without a Windows client.

## Features
- Microphone capture with AVAudioEngine
- VBAN AUDIO transmitter: 48 kHz, PCM16, mono, UDP
- Default UDP port 6980
- Configurable stream name and PC IPv4
- Background audio mode
- Live Activity + Dynamic Island
- Mute/unmute via LiveActivityIntent
- Muted state sends zero-valued PCM while keeping the stream alive

## VoiceMeeter setup
1. Open VoiceMeeter -> VBAN.
2. Enable VBAN.
3. Enable one VBAN IN stream.
4. Set Stream Name to exactly the same value used by MisMeeter (default `MisMeeter`).
5. Use UDP port 6980 unless changed.
6. Enter your Windows LAN IPv4 in MisMeeter.
7. Allow VoiceMeeter/VBAN through Windows Firewall.

## Build
GitHub Actions -> Build unsigned iOS IPA -> download `MisMeeter-unsigned`.

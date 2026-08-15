# MisMeeter v0.4

iPhone microphone -> VBAN -> VoiceMeeter, with no Windows client.

## v0.4 changes

- 3 independent VBAN presets
- smoother VBAN packet pacing
- fixed 256-sample packet cadence at 48 kHz
- software microphone gain control
- default microphone gain: +12 dB
- switched away from AVAudioSession `.measurement` mode
- peak meter
- mute keeps sending silence so VoiceMeeter's stream remains alive
- Live Activity / Dynamic Island controls retained

## VBAN format

- 48,000 Hz
- PCM signed Int16
- Mono
- 256 samples per packet
- UDP
- default port 6980

At 48 kHz, 256 samples represent about 5.333 ms of audio. MisMeeter v0.4 uses a paced sender instead of sending packets in bursts whenever the audio callback happens.

## Presets

Each preset stores:

- display name
- Windows PC IPv4 / hostname
- UDP port
- VBAN stream name

Select Preset 1, 2, or 3 before starting.

Example:

Preset 1
- Name: Desktop
- Host: 192.168.1.50
- Port: 6980
- Stream: MisMeeter

Preset 2
- Name: Gaming
- Host: 192.168.1.50
- Port: 6980
- Stream: MicGame

Preset 3
- Name: Laptop
- Host: 192.168.1.80
- Port: 6980
- Stream: iPhoneMic

## VoiceMeeter

Open VoiceMeeter -> VBAN and enable a VBAN IN stream whose Stream Name matches the selected MisMeeter preset.

If you use multiple presets on the same PC, configure multiple VBAN IN rows with the corresponding stream names.

Windows Firewall must allow UDP traffic to VoiceMeeter on the configured port.

## Microphone gain

The default software gain is +12 dB. You can change it from 0 to +24 dB.

If the signal clips, lower the gain.

## Build

GitHub Actions -> Build unsigned iOS IPA -> download `MisMeeter-unsigned`.

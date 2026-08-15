# MisMeeter v0.5

iPhone microphone -> VBAN -> VoiceMeeter, without a Windows client.

## v0.5 audio fix

v0.4 used a second software clock: a DispatchSourceTimer sent one VBAN packet every ~5.33 ms.
That improved packet spacing but it could slowly drift against the real iPhone audio clock and
periodically produce underruns / short silence packets.

v0.5 removes that clock entirely.

The microphone sample stream is now the only master clock:

AVAudioEngine -> PCM FIFO -> every complete 256 samples -> VBAN UDP

If iOS produces 512 or 1024 frames in one callback, MisMeeter sends 2 or 4 consecutive VBAN
packets. This is valid and expected by VBAN receivers such as VoiceMeeter.

Additional changes:

- UDP connection uses Network.framework `interactiveVoice` service class
- keeps the 0...+24 dB software gain slider
- keeps all 3 independent presets
- requests a 256-sample-like I/O duration, then displays the *actual* duration chosen by iOS
- displays callback frame count and packets sent for diagnostics
- mute remains immediate and sends zero PCM while muted

## VoiceMeeter recommendation

If Wi-Fi still causes intermittent artifacts, increase the VBAN IN **Network Quality** setting
one step (for example Fast -> Medium). That increases receive buffering/latency but improves
tolerance to Wi-Fi jitter.

## VBAN format

- 48 kHz
- signed PCM16
- mono
- 256 samples per VBAN frame
- UDP
- default port 6980

## Presets

Preset 1, Preset 2, and Preset 3 independently store:

- preset name
- PC IPv4 / hostname
- UDP port
- VBAN stream name

## Build

GitHub Actions -> Build unsigned iOS IPA -> download `MisMeeter-unsigned`.

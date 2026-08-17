# MisMeeter v1.3 — Duplex VBAN

MisMeeter can now operate in both directions independently.

## MIC -> VBAN

Existing transmitter:

iPhone microphone -> VBAN UDP -> VoiceMeeter

Features retained:
- 3 TX presets
- gain 0...+24 dB
- Apple Voice Processing
- Live Activity / Dynamic Island
- mute
- direct realtime UDP

## VBAN -> iPhone

New independent receiver:

VoiceMeeter VBAN OUT -> UDP -> MisMeeter -> iPhone speaker

Features:
- 3 completely separate RX presets
- each RX preset stores:
  - name
  - local UDP listen port
  - VBAN stream name
  - jitter-buffer size
- PCM16 48 kHz
- mono streams duplicated to L/R
- stereo streams preserved
- realtime AVAudioSourceNode playback
- jitter buffer with automatic re-prime after an underflow
- packet/loss/underflow diagnostics

TX and RX can be:
- both OFF
- TX only
- RX only
- TX + RX simultaneously

## VoiceMeeter RX setup

To listen on the iPhone:

1. Find the iPhone LAN IPv4 address.
2. In VoiceMeeter VBAN OUT create/enable a stream.
3. Destination IP = iPhone IPv4.
4. Destination port = selected MisMeeter RX preset port.
5. Stream Name = exact MisMeeter RX stream name.
6. Use 48 kHz PCM16 mono or stereo.
7. Press Start Listening in MisMeeter.

If Wi-Fi jitter is audible, increase the RX preset Jitter Buffer slider.
Start around 100 ms.

## Audio-session coexistence

When microphone TX is active, MisMeeter uses playAndRecord so speaker RX can run at the same time.
Stopping TX does not deactivate the iOS audio session when RX is still active, and stopping RX does
not deactivate it while TX is still active.

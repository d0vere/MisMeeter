# MisMeeter v0.9 — Realtime Core Audio + Apple Voice Processing

## Screen-lock fix

v0.8 produced excellent foreground audio but could fragment after the iPhone locked.
The remaining weak point was the software DispatchSourceTimer used to pace VBAN.

v0.9 removes that timer.

Microphone capture now uses AVAudioSinkNode, Apple's realtime input-chain node intended for
realtime/VoIP processing. The audio render callback itself becomes the VBAN master clock.

Pipeline:

iPhone mic
-> optional Apple Voice Processing
-> AVAudioSinkNode realtime callback
-> PCM16 conversion
-> VBAN packetizer
-> UDP / VoiceMeeter

There is no independent packet timer to be throttled/coalesced by screen lock.

## Apple Voice Processing

A new toggle enables Apple's VoiceProcessingIO processing.

Apple's voice processing stack is designed for spoken voice and includes processing such as:
- noise suppression
- automatic gain control / voice gain processing
- echo cancellation

The audio engine must be stopped when enabling/disabling voice processing, so the toggle is
disabled while VBAN is streaming.

When enabled, MisMeeter uses:
- AVAudioSession category: playAndRecord
- mode: voiceChat
- AVAudioInputNode.setVoiceProcessingEnabled(true)

When disabled it keeps the more neutral recording path.

## Existing features retained

- 3 VBAN presets
- 0...+24 dB software gain
- Live Activity / Dynamic Island mute
- background audio
- direct VBAN UDP
- PCM16 / mono / 48 kHz

## First test

1. VoiceMeeter VBAN Network Quality: try Optimal first.
2. Start MisMeeter with Apple Voice Processing OFF.
3. Verify Input callback. With AVAudioSinkNode it should ideally be close to the hardware quantum,
   not the old 4800-frame tap callback.
4. Lock the iPhone for at least 30 seconds and listen.
5. Then stop VBAN, enable Apple Voice Processing, restart and compare noise/voice quality.

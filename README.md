# MisMeeter v0.6

iPhone microphone -> VBAN -> VoiceMeeter, without a Windows client.

## Why v0.6 exists

On the test iPhone, MisMeeter reports:

- actual AVAudioSession I/O buffer: about 5.33 ms
- AVAudioEngine tap callback: 4800 frames
- 4800 frames at 48 kHz = exactly 100 ms
- FIFO remainder cycles 0 -> 64 -> 128 -> 192 because 4800 mod 256 = 192

That means the microphone callback can batch roughly 100 ms of audio even though the
hardware I/O cycle itself is much smaller.

v0.5 immediately converted those large callbacks into 18/19 VBAN packets, creating a
100 ms packet burst. VoiceMeeter Network Quality = Medium can absorb that burst, while
Fast/Optimal may sound fragmented.

## v0.6 smoothing

v0.6 does this instead:

AVAudioEngine
    -> large 4800-sample callbacks
    -> FIFO / prebuffer
    -> smooth pacer
    -> one 256-sample VBAN frame every ~5.33 ms
    -> VoiceMeeter

The sender also applies a tiny adaptive clock correction (a few tenths of one percent)
based on FIFO occupancy. This prevents long-term drift between iPhone capture timing and
the software sender clock.

## TX modes

### Low Latency
About 100 ms startup prebuffer.
Try this first with VoiceMeeter Fast.

### Balanced
About 200 ms startup prebuffer.
Recommended default.

### Maximum
About 300 ms startup prebuffer.
Designed to maximize smoothness and give VoiceMeeter Optimal/Fast the cleanest packet cadence.

The mode affects latency/stability only. Audio remains:
- 48 kHz
- PCM16
- mono
- 256 samples per VBAN packet

## Existing features retained

- 3 independent VBAN presets
- 0...+24 dB software microphone gain
- Live Activity / Dynamic Island
- immediate real stream mute
- background audio
- direct VBAN UDP, no Windows client

## Diagnostics

Status now shows:

- Sender buffer
- Input callback frames
- Actual I/O buffer
- Sender primed
- Underruns
- Packets sent

For a healthy stream after startup, Underruns should remain at 0.

# MisMeeter 3.3.4 — Native VBAN for iOS

MisMeeter is a native iOS app for real-time **VBAN audio transmission and reception** over local networks. It was created as a modern alternative to **VBAN Talkie**, which is no longer actively updated and lacks integration with current iOS features.

## Features

- VBAN microphone transmission and audio reception
- Independent Mic and RX mute
- Live Activity + Dynamic Island status
- Two native iOS 18 Controls for **Mic** and **RX** on Control Center / Lock Screen
- Automatic low-latency adaptive receive jitter
- Native Swift / SwiftUI, local processing, no cloud required

## 3.3.4

The Dynamic Island is exclusively ActivityKit-driven. In compact mode, **RX** and **TX** are grouped together on the **left side of the camera/sensor area**; the compact trailing region is empty.

The two native Controls are stateful and runtime-authoritative:

- **MisMeeter Mic** — ON = microphone transmitting, OFF = microphone muted, IDLE = TX inactive
- **MisMeeter RX** — ON = receive audio audible, OFF = receive audio muted, IDLE = RX inactive

Control actions use exact desired values, `.alwaysAllowed`, and `openAppWhenRun = false`. They never start an inactive transport and never publish speculative state.

There is **no MediaPlayer, Now Playing, silent audio, remote media command, or legacy queued TX layer** in the generated Xcode targets.

## Requirements

- iOS 18.5+
- Xcode 16.4+
- Microphone and Local Network permissions
- A compatible VBAN endpoint

**A modern VBAN audio companion built natively for iOS.**

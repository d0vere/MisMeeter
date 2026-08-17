import AVFoundation
import Foundation
import MediaPlayer

/// Owns MisMeeter's temporary Now Playing surface while TX is already active.
/// Important: remote Play never starts VBAN or launches a new MisMeeter session.
final class NowPlayingRemoteController {
    static let shared = NowPlayingRemoteController()

    private var silentPlayer: AVAudioPlayer?
    private var commandTokens: [(MPRemoteCommand, Any)] = []
    private var routeObserver: NSObjectProtocol?
    private var isInstalled = false

    private var isTXActive: (() -> Bool)?
    private var isRXActive: (() -> Bool)?
    private var isMicrophoneMuted: (() -> Bool)?
    private var setMicrophoneMuted: ((Bool) -> Void)?
    private var toggleReceiveMute: (() -> Void)?
    private var stopAll: (() -> Void)?

    private init() {}

    func activate(
        isTXActive: @escaping () -> Bool,
        isRXActive: @escaping () -> Bool,
        isMicrophoneMuted: @escaping () -> Bool,
        setMicrophoneMuted: @escaping (Bool) -> Void,
        toggleReceiveMute: @escaping () -> Void,
        stopAll: @escaping () -> Void
    ) {
        self.isTXActive = isTXActive
        self.isRXActive = isRXActive
        self.isMicrophoneMuted = isMicrophoneMuted
        self.setMicrophoneMuted = setMicrophoneMuted
        self.toggleReceiveMute = toggleReceiveMute
        self.stopAll = stopAll

        installRouteObserverIfNeeded()
        refreshForCurrentRoute()
    }

    func syncState() {
        guard isInstalled else { return }
        updateNowPlayingInfo()
    }

    func deactivate() {
        removeRemoteCommands()
        silentPlayer?.stop()
        silentPlayer = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        isInstalled = false

        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
    }

    private func refreshForCurrentRoute() {
        guard isTXActive?() == true else {
            deactivateNowPlayingOnly()
            return
        }

        // A car/Bluetooth accessory must remain available to the user's real media app.
        // Apple does not expose the physical source of an MPRemoteCommandEvent, therefore
        // MisMeeter withdraws from Now Playing whenever such a route/accessory is detected.
        guard !hasCarOrBluetoothAudioRoute else {
            deactivateNowPlayingOnly()
            return
        }

        installRemoteCommandsIfNeeded()
        prepareSilentPlayerIfNeeded()
        if isMicrophoneMuted?() == true {
            silentPlayer?.pause()
        } else {
            silentPlayer?.play()
        }
        updateNowPlayingInfo()
    }

    private var hasCarOrBluetoothAudioRoute: Bool {
        let session = AVAudioSession.sharedInstance()
        let protectedTypes: Set<AVAudioSession.Port> = [
            .carAudio,
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE
        ]

        if session.currentRoute.outputs.contains(where: { protectedTypes.contains($0.portType) }) {
            return true
        }
        if session.currentRoute.inputs.contains(where: { protectedTypes.contains($0.portType) }) {
            return true
        }
        // HFP/car accessories can be discoverable as inputs even when MisMeeter currently
        // forces its own output to the iPhone speaker.
        if session.availableInputs?.contains(where: { protectedTypes.contains($0.portType) }) == true {
            return true
        }
        return false
    }

    private func installRouteObserverIfNeeded() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            self?.refreshForCurrentRoute()
        }
    }

    private func installRemoteCommandsIfNeeded() {
        guard !isInstalled else { return }
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true

        commandTokens.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in
            guard let self, self.isTXActive?() == true, !self.hasCarOrBluetoothAudioRoute else {
                return .commandFailed
            }
            // Play only unmutes an already-running TX. It never calls runtime.start().
            self.setMicrophoneMuted?(false)
            self.silentPlayer?.play()
            self.updateNowPlayingInfo()
            return .success
        }))

        commandTokens.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isTXActive?() == true, !self.hasCarOrBluetoothAudioRoute else {
                return .commandFailed
            }
            self.setMicrophoneMuted?(true)
            self.silentPlayer?.pause()
            self.updateNowPlayingInfo()
            return .success
        }))

        commandTokens.append((center.previousTrackCommand, center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isTXActive?() == true, self.isRXActive?() == true, !self.hasCarOrBluetoothAudioRoute else {
                return .commandFailed
            }
            self.toggleReceiveMute?()
            self.updateNowPlayingInfo()
            return .success
        }))

        commandTokens.append((center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isTXActive?() == true, !self.hasCarOrBluetoothAudioRoute else {
                return .commandFailed
            }
            self.deactivateNowPlayingOnly()
            self.stopAll?()
            return .success
        }))

        center.togglePlayPauseCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        center.changePlaybackRateCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false

        isInstalled = true
    }

    private func removeRemoteCommands() {
        for (command, token) in commandTokens {
            command.removeTarget(token)
        }
        commandTokens.removeAll()

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = false
        center.pauseCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.nextTrackCommand.isEnabled = false
        isInstalled = false
    }

    private func deactivateNowPlayingOnly() {
        removeRemoteCommands()
        silentPlayer?.pause()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func prepareSilentPlayerIfNeeded() {
        guard silentPlayer == nil,
              let url = Bundle.main.url(forResource: "mismeeter-silence", withExtension: "wav") else {
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            silentPlayer = player
        } catch {
            print("MISMEETER: silent Now Playing source error: \(error)")
        }
    }

    private func updateNowPlayingInfo() {
        guard isInstalled, isTXActive?() == true else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let muted = isMicrophoneMuted?() ?? false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: muted ? "Microfono mutato" : "Microfono attivo",
            MPMediaItemPropertyArtist: "MisMeeter · ⏮ Mute RX · ⏭ Stop All",
            MPMediaItemPropertyPlaybackDuration: 3600.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: muted ? 0.0 : 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
    }
}

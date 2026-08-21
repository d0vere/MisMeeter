import AVFoundation
import Foundation
import MediaPlayer

/// Owns MisMeeter's temporary Now Playing surface while TX is already active.
/// Remote Play never starts VBAN or launches a new MisMeeter session.
///
/// The keep-alive AVQueuePlayer always remains physically playing while TX is active,
/// even when the microphone is logically muted. The logical play/pause state is
/// published manually through Now Playing metadata. This prevents iOS from treating
/// the session as dormant and graying out Lock Screen controls after a pause/mute.
final class NowPlayingRemoteController {
    static let shared = NowPlayingRemoteController()

    private let externalRouteGraceSeconds: TimeInterval = 6

    private var keepAlivePlayer: AVQueuePlayer?
    private var keepAliveLooper: AVPlayerLooper?
    private var nowPlayingSession: MPNowPlayingSession?
    private var commandTokens: [(MPRemoteCommand, Any)] = []

    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private var routeRestoreWorkItem: DispatchWorkItem?
    private var promotionRetryWorkItem: DispatchWorkItem?
    private var promotionRetryCount = 0

    private var externalRouteSuppressedUntil: Date?
    private var isInstalled = false

    private var isTXActive: (() -> Bool)?
    private var isRXActive: (() -> Bool)?
    private var isMicrophoneMuted: (() -> Bool)?
    private var toggleMicrophoneMute: (() -> Bool)?
    private var toggleReceiveMute: (() -> Void)?
    private var stopAll: (() -> Void)?
    private var onSessionPromoted: (() -> Void)?

    private init() {}

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func activate(
        isTXActive: @escaping () -> Bool,
        isRXActive: @escaping () -> Bool,
        isMicrophoneMuted: @escaping () -> Bool,
        toggleMicrophoneMute: @escaping () -> Bool,
        toggleReceiveMute: @escaping () -> Void,
        stopAll: @escaping () -> Void,
        onSessionPromoted: @escaping () -> Void
    ) {
        self.isTXActive = isTXActive
        self.isRXActive = isRXActive
        self.isMicrophoneMuted = isMicrophoneMuted
        self.toggleMicrophoneMute = toggleMicrophoneMute
        self.toggleReceiveMute = toggleReceiveMute
        self.stopAll = stopAll
        self.onSessionPromoted = onSessionPromoted

        performOnMain { [weak self] in
            guard let self else { return }
            self.installObserversIfNeeded()
            self.refreshForCurrentRoute()
        }
    }

    func syncState() {
        performOnMain { [weak self] in
            guard let self else { return }
            guard self.isTXActive?() == true else {
                self.deactivateNowPlayingOnly()
                return
            }

            self.refreshForCurrentRoute()
        }
    }

    func deactivate() {
        performOnMain { [weak self] in
            guard let self else { return }

            self.routeRestoreWorkItem?.cancel()
            self.routeRestoreWorkItem = nil
            self.promotionRetryWorkItem?.cancel()
            self.promotionRetryWorkItem = nil
            self.promotionRetryCount = 0
            self.externalRouteSuppressedUntil = nil

            self.deactivateNowPlayingOnly()

            if let routeObserver = self.routeObserver {
                NotificationCenter.default.removeObserver(routeObserver)
                self.routeObserver = nil
            }
            if let interruptionObserver = self.interruptionObserver {
                NotificationCenter.default.removeObserver(interruptionObserver)
                self.interruptionObserver = nil
            }
            if let mediaResetObserver = self.mediaResetObserver {
                NotificationCenter.default.removeObserver(mediaResetObserver)
                self.mediaResetObserver = nil
            }
        }
    }

    private func refreshForCurrentRoute() {
        precondition(Thread.isMainThread)

        guard isTXActive?() == true else {
            deactivateNowPlayingOnly()
            return
        }

        // Apple does not expose whether an MPRemoteCommandEvent originated from the
        // Lock Screen or a physical Bluetooth/car button. MisMeeter therefore yields
        // while an external route is actually in use and for a short grace period
        // immediately after a new external accessory appears.
        guard !shouldYieldNowPlayingToExternalMedia else {
            deactivateNowPlayingOnly()
            return
        }

        do {
            try AudioSessionCoordinator.shared.ensureActive()
            try prepareNowPlayingSessionIfNeeded()
        } catch {
            print("MISMEETER: Now Playing activation error: \(error)")
            deactivateNowPlayingOnly()
            return
        }

        installRemoteCommandsIfNeeded()
        keepAlivePlayer?.playImmediately(atRate: 1.0)
        updateNowPlayingInfo()
        promoteSessionIfPossible()
    }

    private var shouldYieldNowPlayingToExternalMedia: Bool {
        hasProtectedCurrentRoute || isExternalRouteGracePeriodActive
    }

    private var hasProtectedCurrentRoute: Bool {
        let session = AVAudioSession.sharedInstance()
        let protectedTypes: Set<AVAudioSession.Port> = [
            .carAudio,
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE,
            .airPlay
        ]

        if session.currentRoute.outputs.contains(where: { protectedTypes.contains($0.portType) }) {
            return true
        }
        if session.currentRoute.inputs.contains(where: { protectedTypes.contains($0.portType) }) {
            return true
        }
        return false
    }

    private var hasAvailableExternalAudioAccessory: Bool {
        let protectedInputs: Set<AVAudioSession.Port> = [
            .carAudio,
            .bluetoothHFP,
            .bluetoothLE
        ]

        return AVAudioSession.sharedInstance().availableInputs?.contains {
            protectedInputs.contains($0.portType)
        } == true
    }

    private var isExternalRouteGracePeriodActive: Bool {
        guard let until = externalRouteSuppressedUntil else { return false }
        return until > Date()
    }

    private func armExternalRouteGracePeriod() {
        precondition(Thread.isMainThread)

        let deadline = Date().addingTimeInterval(externalRouteGraceSeconds)
        externalRouteSuppressedUntil = deadline

        routeRestoreWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.externalRouteSuppressedUntil == deadline {
                self.externalRouteSuppressedUntil = nil
            }
            self.refreshForCurrentRoute()
        }
        routeRestoreWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + externalRouteGraceSeconds + 0.1,
            execute: workItem
        )
    }

    private func installObserversIfNeeded() {
        if routeObserver == nil {
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }

                if let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue),
                   reason == .newDeviceAvailable,
                   self.hasAvailableExternalAudioAccessory {
                    self.armExternalRouteGracePeriod()
                }

                self.refreshForCurrentRoute()
            }
        }

        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            }
        }

        if mediaResetObserver == nil {
            mediaResetObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.deactivateNowPlayingOnly()
                self.refreshForCurrentRoute()
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            // Keep handlers/metadata installed. The system may temporarily deactivate
            // our audio session, but tearing down Now Playing here makes recovery less reliable.
            keepAlivePlayer?.pause()

        case .ended:
            guard isTXActive?() == true else {
                deactivateNowPlayingOnly()
                return
            }

            if let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                if !options.contains(.shouldResume) {
                    updateNowPlayingInfo()
                    return
                }
            }

            refreshForCurrentRoute()

        @unknown default:
            break
        }
    }

    private func prepareNowPlayingSessionIfNeeded() throws {
        precondition(Thread.isMainThread)

        if let player = keepAlivePlayer,
           let session = nowPlayingSession {
            if player.rate == 0 {
                player.playImmediately(atRate: 1.0)
            }
            session.automaticallyPublishesNowPlayingInfo = false
            return
        }

        guard let url = Bundle.main.url(
            forResource: "mismeeter-silence",
            withExtension: "wav"
        ) else {
            throw NowPlayingError.missingSilenceResource
        }

        let player = AVQueuePlayer()
        player.volume = 1.0 // the bundled WAV itself contains digital silence
        player.actionAtItemEnd = .none

        let templateItem = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: player, templateItem: templateItem)
        let session = MPNowPlayingSession(players: [player])
        session.automaticallyPublishesNowPlayingInfo = false

        keepAlivePlayer = player
        keepAliveLooper = looper
        nowPlayingSession = session
        promotionRetryCount = 0

        player.playImmediately(atRate: 1.0)
    }

    private func isRemoteCommandAllowed() -> Bool {
        if Thread.isMainThread {
            return !shouldYieldNowPlayingToExternalMedia
        }
        return DispatchQueue.main.sync {
            !shouldYieldNowPlayingToExternalMedia
        }
    }

    private func installRemoteCommandsIfNeeded() {
        precondition(Thread.isMainThread)
        guard !isInstalled,
              let center = nowPlayingSession?.remoteCommandCenter else {
            return
        }

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true

        // The physical keep-alive player intentionally stays in the playing state.
        // iOS can therefore show either Play or Pause depending on its own cached media state.
        // Treat both commands as the same atomic microphone toggle so the Lock Screen can
        // never get out of sync with a mute performed from inside the app or another surface.
        commandTokens.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in
            self?.handleRemoteMicrophoneToggle() ?? .commandFailed
        }))

        commandTokens.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteMicrophoneToggle() ?? .commandFailed
        }))

        commandTokens.append((center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteMicrophoneToggle() ?? .commandFailed
        }))

        commandTokens.append((center.previousTrackCommand, center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self,
                  self.isTXActive?() == true,
                  self.isRXActive?() == true,
                  self.isRemoteCommandAllowed() else {
                return .commandFailed
            }

            self.toggleReceiveMute?()
            self.schedulePostCommandRefresh()
            return .success
        }))

        commandTokens.append((center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self,
                  self.isTXActive?() == true,
                  self.isRemoteCommandAllowed() else {
                return .commandFailed
            }

            DispatchQueue.main.async { [weak self] in
                self?.deactivateNowPlayingOnly()
            }
            self.stopAll?()
            return .success
        }))

        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        center.changePlaybackRateCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.stopCommand.isEnabled = false

        isInstalled = true
    }


    private func handleRemoteMicrophoneToggle() -> MPRemoteCommandHandlerStatus {
        guard isTXActive?() == true,
              isRemoteCommandAllowed(),
              let toggleMicrophoneMute else {
            return .commandFailed
        }

        _ = toggleMicrophoneMute()
        schedulePostCommandRefresh()
        return .success
    }

    private func schedulePostCommandRefresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Never pause the physical keep-alive player for logical microphone mute.
            if self.keepAlivePlayer?.rate == 0 {
                self.keepAlivePlayer?.playImmediately(atRate: 1.0)
            }
            self.updateNowPlayingInfo()
            self.promoteSessionIfPossible()
        }
    }

    private func removeRemoteCommands() {
        precondition(Thread.isMainThread)

        for (command, token) in commandTokens {
            command.removeTarget(token)
        }
        commandTokens.removeAll()

        if let center = nowPlayingSession?.remoteCommandCenter {
            center.playCommand.isEnabled = false
            center.pauseCommand.isEnabled = false
            center.togglePlayPauseCommand.isEnabled = false
            center.previousTrackCommand.isEnabled = false
            center.nextTrackCommand.isEnabled = false
        }

        isInstalled = false
    }

    private func deactivateNowPlayingOnly() {
        precondition(Thread.isMainThread)

        removeRemoteCommands()
        nowPlayingSession?.nowPlayingInfoCenter.nowPlayingInfo = nil
        keepAlivePlayer?.pause()
        keepAliveLooper?.disableLooping()
        keepAliveLooper = nil
        keepAlivePlayer?.removeAllItems()

        keepAlivePlayer = nil
        nowPlayingSession = nil
        promotionRetryWorkItem?.cancel()
        promotionRetryWorkItem = nil
        promotionRetryCount = 0
    }

    private func updateNowPlayingInfo() {
        precondition(Thread.isMainThread)

        guard isInstalled,
              isTXActive?() == true,
              let infoCenter = nowPlayingSession?.nowPlayingInfoCenter else {
            nowPlayingSession?.nowPlayingInfoCenter.nowPlayingInfo = nil
            return
        }

        let microphoneMuted = isMicrophoneMuted?() ?? false
        let rxText: String
        if isRXActive?() == true {
            rxText = "⏮ Mute RX"
        } else {
            rxText = "⏮ RX unavailable"
        }

        infoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: microphoneMuted ? "Microphone muted" : "Microphone active",
            MPMediaItemPropertyArtist: "MisMeeter · \(rxText) · ⏭ Stop All",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: microphoneMuted ? 0.0 : 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyExternalContentIdentifier: "dev.mismeeter.active-vban-session"
        ]
    }

    private func promoteSessionIfPossible() {
        precondition(Thread.isMainThread)
        guard let session = nowPlayingSession, !session.isActive else {
            promotionRetryCount = 0
            promotionRetryWorkItem?.cancel()
            promotionRetryWorkItem = nil
            return
        }

        guard session.canBecomeActive else {
            schedulePromotionRetry()
            return
        }

        session.becomeActiveIfPossible { [weak self] becameActive in
            DispatchQueue.main.async {
                guard let self else { return }
                if becameActive {
                    self.promotionRetryCount = 0
                    self.promotionRetryWorkItem?.cancel()
                    self.promotionRetryWorkItem = nil
                    self.onSessionPromoted?()
                } else {
                    self.schedulePromotionRetry()
                }
            }
        }
    }

    private func schedulePromotionRetry() {
        precondition(Thread.isMainThread)
        guard isTXActive?() == true,
              !shouldYieldNowPlayingToExternalMedia,
              promotionRetryCount < 8 else {
            return
        }

        promotionRetryCount += 1
        promotionRetryWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.promoteSessionIfPossible()
        }
        promotionRetryWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.25,
            execute: workItem
        )
    }
}

private enum NowPlayingError: LocalizedError {
    case missingSilenceResource

    var errorDescription: String? {
        switch self {
        case .missingSilenceResource:
            return "The bundled silent audio resource is missing."
        }
    }
}

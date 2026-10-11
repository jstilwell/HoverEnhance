import AVFoundation

/// Owns the preview's video player: applies the remembered mute and volume, loops, and remembers
/// where each video stopped so reopening it picks up there.
@MainActor
final class VideoPlayback {
    private(set) var player: AVPlayer?
    private var key: String?
    /// Seconds into each video, by key, for videos closed partway through.
    private var positions: [String: Double] = [:]
    private var loopObserver: NSObjectProtocol?
    private var settingObservations: [NSKeyValueObservation] = []

    init() {
        UserDefaults.standard.register(defaults: ["videoMuted": true, "videoVolume": 1.0])
    }

    /// Starts `url` and waits until it has a frame to show. Returns the video's size, or nil if it
    /// failed, timed out, or was replaced. `key` identifies the video for resuming.
    func start(_ url: URL, key: String) async -> CGSize? {
        stop()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // AirPlay device discovery would make macOS ask for local network access.
        player.allowsExternalPlayback = false
        player.isMuted = UserDefaults.standard.bool(forKey: "videoMuted")
        player.volume = UserDefaults.standard.float(forKey: "videoVolume")
        self.player = player
        self.key = key

        // Remember mute and volume changes made with the player's controls.
        settingObservations = [
            player.observe(\.isMuted) { player, _ in UserDefaults.standard.set(player.isMuted, forKey: "videoMuted") },
            player.observe(\.volume) { player, _ in UserDefaults.standard.set(player.volume, forKey: "videoVolume") },
        ]
        loopObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline, item.status != .failed {
            guard !Task.isCancelled, self.player === player else { return nil }
            if item.status == .readyToPlay, item.presentationSize != .zero {
                if let seconds = positions[key] {
                    log.info("resuming \(key, privacy: .public) at \(seconds, format: .fixed(precision: 1))s")
                    await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                }
                guard self.player === player else { return nil }
                player.play()
                return item.presentationSize
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if self.player === player { stop() }
        return nil
    }

    /// Pauses, remembers the position, and lets the player go.
    func stop() {
        guard let player, let key else { return }
        let time = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? .nan
        // Remember partway positions; a video watched to the end starts over next time.
        let partway = time.isFinite && time > 1 && !(duration.isFinite && time > duration - 1)
        positions[key] = partway ? time : nil

        player.pause()
        settingObservations = []
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        self.player = nil
        self.key = nil
    }
}

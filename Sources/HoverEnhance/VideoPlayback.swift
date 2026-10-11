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
    /// Where an in-flight scrub is headed, so quick scrolls add up instead of restarting from a
    /// position that hasn't caught up yet.
    private var scrubTarget: Double?
    private var settingObservations: [NSKeyValueObservation] = []
    /// Called on the main thread when the player's volume or mute changes, by scrolling or its controls.
    var onVolumeChange: (@MainActor (_ level: Float, _ muted: Bool) -> Void)?

    /// The player's volume and mute, while there's a player.
    var volume: (level: Float, muted: Bool)? {
        player.map { ($0.volume, $0.isMuted) }
    }

    /// Starts `url` and waits until it has a frame to show. Returns the video's size, or nil if it
    /// failed, timed out, or was replaced. `key` identifies the video for resuming.
    func start(_ url: URL, key: String) async -> CGSize? {
        stop()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // AirPlay device discovery would make macOS ask for local network access.
        player.allowsExternalPlayback = false
        let settings = AppSettings.shared
        player.isMuted = settings.videosStartMuted
        player.volume = Float(settings.videoVolume)
        self.player = player
        self.key = key

        // Remember mute and volume changes made with the player's controls.
        settingObservations = [
            player.observe(\.isMuted) { [weak self] player, _ in
                let (muted, level) = (player.isMuted, player.volume)
                Task { @MainActor in
                    if AppSettings.shared.videoSound == .remember { AppSettings.shared.videoMuted = muted }
                    self?.onVolumeChange?(level, muted)
                }
            },
            player.observe(\.volume) { [weak self] player, _ in
                let (muted, level) = (player.isMuted, player.volume)
                Task { @MainActor in
                    AppSettings.shared.videoVolume = Double(level)
                    self?.onVolumeChange?(level, muted)
                }
            },
        ]
        if settings.loopVideos {
            loopObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline, item.status != .failed {
            guard !Task.isCancelled, self.player === player else { return nil }
            if item.status == .readyToPlay, item.presentationSize != .zero {
                if settings.resumeVideos, let seconds = positions[key] {
                    log.infoPrivateInRelease("resuming \(key) at \(String(format: "%.1f", seconds))s")
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

    /// Moves playback by `seconds`. Returns the new position for display, like "1:23 / 2:45".
    func scrub(by seconds: Double) -> String? {
        guard let player, let item = player.currentItem else { return nil }
        let duration = item.duration.seconds
        var target = (scrubTarget ?? player.currentTime().seconds) + seconds
        target = duration.isFinite ? min(max(target, 0), max(duration - 0.1, 0)) : max(target, 0)
        scrubTarget = target
        let destination = target
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: destination, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor [self] in
                if self?.scrubTarget == destination { self?.scrubTarget = nil }
            }
        }
        return duration.isFinite ? "\(Self.clock(target)) / \(Self.clock(duration))" : Self.clock(target)
    }

    /// Changes the volume by `amount` (of 1). Scrolling up from muted unmutes, starting quiet.
    func changeVolume(by amount: Double) {
        guard let player else { return }
        if player.isMuted {
            guard amount > 0 else { return }
            player.volume = Float(amount)
            player.isMuted = false
        } else {
            player.volume = Float(min(max(Double(player.volume) + amount, 0), 1))
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Pauses, remembers the position, and lets the player go.
    func stop() {
        guard let player, let key else { return }
        let time = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? .nan
        // Remember partway positions; a video watched to the end starts over next time.
        let partway = AppSettings.shared.resumeVideos && time.isFinite && time > 1 && !(duration.isFinite && time > duration - 1)
        positions[key] = partway ? time : nil

        player.pause()
        scrubTarget = nil
        settingObservations = []
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        self.player = nil
        self.key = nil
    }
}

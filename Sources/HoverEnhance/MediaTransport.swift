import AVFoundation
import SwiftUI

/// Where a Finder song or video is, for the controls under it: playing or not, how far in, how long it
/// is, and whether its sound is on. Follows the player it's attached to, however that player is moved.
@MainActor @Observable
final class MediaTransport {
    private(set) var isPlaying = false
    private(set) var isMuted = false
    /// Seconds in, or where a drag on the scrubber has taken it.
    private(set) var elapsed: Double = 0
    /// Seconds, once known.
    private(set) var duration: Double?
    /// Whether there's a player to control. A song that hasn't been started has none.
    private(set) var isAttached = false
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// While the scrubber is dragged, the player's time doesn't pull it back.
    @ObservationIgnored private var isScrubbing = false
    /// Starts playback while there's no player.
    @ObservationIgnored private let start: (@MainActor () -> Void)?

    init(duration: Double?, start: (@MainActor () -> Void)? = nil) {
        self.duration = duration
        self.start = start
    }

    /// Reads the file's length, when its details left it out.
    func loadDuration(of url: URL) {
        guard duration == nil else { return }
        Task {
            guard let seconds = await Self.length(of: url), duration == nil else { return }
            duration = seconds
        }
    }

    private nonisolated static func length(of url: URL) async -> Double? {
        guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    func attach(_ player: AVPlayer) {
        detach()
        self.player = player
        isAttached = true
        update()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        observations = [
            player.observe(\.timeControlStatus) { [weak self] _, _ in Task { @MainActor in self?.update() } },
            player.observe(\.isMuted) { [weak self] _, _ in Task { @MainActor in self?.update() } },
        ]
    }

    /// Stops following the player, before the transport or the player is let go.
    func detach() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations = []
        player = nil
        isAttached = false
        isPlaying = false
    }

    private func update() {
        guard let player else { return }
        isPlaying = player.timeControlStatus != .paused
        isMuted = player.isMuted
        if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 { duration = seconds }
        let now = player.currentTime().seconds
        if !isScrubbing, now.isFinite { elapsed = now }
    }

    func toggle() {
        guard let player else {
            start?()
            return
        }
        if player.timeControlStatus != .paused {
            player.pause()
        } else {
            // Played to the end, it starts over.
            if let duration, elapsed >= duration - 0.25 { player.seek(to: .zero) }
            player.play()
        }
    }

    func toggleMute() {
        player?.isMuted.toggle()
    }

    /// Moves to `fraction` of the way through, as the scrubber is dragged; `done` at the end of the drag.
    func scrub(to fraction: Double, done: Bool) {
        guard let player, let duration else { return }
        let target = min(max(fraction, 0), 1) * duration
        isScrubbing = true
        elapsed = target
        // Close enough while dragging, so seeks keep up; exact where it's let go.
        let tolerance = done ? CMTime.zero : CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            guard done else { return }
            Task { @MainActor in self?.isScrubbing = false }
        }
    }

    /// Moves by `seconds`, for VoiceOver's adjust actions.
    func skip(by seconds: Double) {
        guard let duration, duration > 0 else { return }
        scrub(to: (elapsed + seconds) / duration, done: true)
    }
}

/// Play and pause, where the song or video is and how much is left, and its sound, under it.
struct TransportBar: View {
    static let height: CGFloat = 32
    let transport: MediaTransport

    var body: some View {
        HStack(spacing: 8) {
            Button { transport.toggle() } label: {
                Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .help(transport.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")

            // Narrow media keeps the scrubber and drops the times.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    time(transport.elapsed)
                    Scrubber(transport: transport).frame(minWidth: 60)
                    // Rounded up, so the two times add up to the whole.
                    time(transport.duration.map { max($0 - transport.elapsed, 0).rounded(.up) }, prefix: "-")
                }
                Scrubber(transport: transport)
            }

            Button { transport.toggleMute() } label: {
                Image(systemName: transport.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .disabled(!transport.isAttached)
            .help(transport.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(transport.isMuted ? "Unmute" : "Mute")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .frame(height: Self.height)
    }

    private func time(_ seconds: Double?, prefix: String = "") -> some View {
        Text(seconds.map { prefix + VideoPlayback.clock($0) } ?? "--:--")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}

/// A track to drag through the song or video, filled as far as it's played.
private struct Scrubber: View {
    let transport: MediaTransport

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = transport.duration.map { $0 > 0 ? min(max(transport.elapsed / $0, 0), 1) : 0 } ?? 0
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                Capsule().fill(.secondary).frame(width: width * fraction, height: 4)
                if transport.isAttached {
                    Circle().fill(.primary).frame(width: 9, height: 9).offset(x: width * fraction - 4.5)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { transport.scrub(to: $0.location.x / width, done: false) }
                    .onEnded { transport.scrub(to: $0.location.x / width, done: true) }
            )
        }
        .frame(height: 20)
        .disabled(!transport.isAttached)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(transport.duration.map { "\(VideoPlayback.clock(transport.elapsed)) of \(VideoPlayback.clock($0))" } ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: transport.skip(by: 10)
            case .decrement: transport.skip(by: -10)
            @unknown default: break
            }
        }
    }
}

import AppKit
import WebKit

/// Decides when to show a preview for what the cursor is resting on, and when to hide it.
@MainActor
final class PreviewController {
    private let fetcher = MediaFetcher()
    private let loader = ImageLoader()
    private let playback = VideoPlayback()
    private let embeds = EmbedPlayer()
    private let panel = PreviewPanel()
    private let scrollTap = ScrollTap()
    private var activationObserver: NSObjectProtocol?

    private var target: Target?
    private var media: Media?
    /// The album position being shown, or being loaded after a scroll.
    private var index = 0
    private var task: Task<Void, Never>?

    private struct Target: Equatable {
        let source: MediaSource
        /// Where the cursor rested, in global top-left-origin coordinates. The preview hangs off it.
        let anchor: CGPoint
        /// The notch under the cursor. Leaving it any way but onto the preview ends the hover.
        let notch: CGRect
        let page: URL?
    }

    init() {
        scrollTap.onStep = { [weak self] step in self?.step(by: step) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset(because: "app switched") }
        }
    }

    func hovered(_ info: HoverInfo) {
        guard let cursor = CGEvent(source: nil)?.location else { return }
        // Resting on the preview or its notch: what's underneath doesn't count.
        if target != nil, panel.covers(cursor) { return }
        let settings = AppSettings.shared
        guard settings.previewsEnabled, settings.previewsAllowed(holding: NSEvent.modifierFlags),
              !settings.isExcluded(info.bundleID) else {
            reset(because: "previews are off here")
            return
        }
        guard let source = MediaResolver.source(for: info), settings.filter.allows(source) else {
            reset(because: "nothing to preview")
            return
        }
        // Still on the same thing: it's loading, showing, or was dismissed by a click.
        if target?.source == source { return }

        reset(because: "new target")
        let elementFrame = info.imageFrame ?? info.frame
        let newTarget = Target(source: source, anchor: cursor, notch: panel.notchFrame(at: cursor), page: info.pageURL)
        target = newTarget
        task = Task {
            guard let fetched = await fetcher.media(for: source), let media = AppSettings.shared.filter.apply(to: fetched),
                  !Task.isCancelled, target == newTarget else { return }
            self.media = media
            // A lone image isn't worth showing unless it's meaningfully bigger than it already appears.
            await display(0, unlessSmallerThan: media.items.count == 1 ? elementFrame?.size : nil)
        }
    }

    /// Ends the hover the moment the cursor leaves the notch, unless it moves onto the preview.
    func mouseMoved(to point: CGPoint) {
        guard let target, !target.notch.contains(point), !panel.covers(point) else { return }
        reset(because: "left the notch")
    }

    /// Content moved under the cursor. While an album is up, the scroll tap has the wheel instead.
    func scrolled() {
        if !scrollTap.isEnabled { reset(because: "scrolled") }
    }

    /// Hides the preview but remembers the target, so it stays hidden until the cursor moves on.
    func dismiss() {
        if target != nil { log.debug("preview dismissed by click") }
        task?.cancel()
        hidePanel()
    }

    func reset(because reason: String = "reset") {
        if target != nil { log.debug("preview hidden: \(reason, privacy: .public)") }
        task?.cancel()
        task = nil
        target = nil
        media = nil
        index = 0
        hidePanel()
    }

    private func hidePanel() {
        // Take the windows down first; stopping playback can take a moment.
        panel.hide()
        scrollTap.isEnabled = false
        playback.stop()
        embeds.suspend()
    }

    private func step(by delta: Int) {
        guard let media, media.items.count > 1 else { return }
        let next = min(max(index + delta, 0), media.items.count - 1)
        guard next != index else { return }
        // Move the index now so quick scrolls add up, even before the item arrives.
        index = next
        task?.cancel()
        task = Task { await display(next) }
    }

    private func display(_ position: Int, unlessSmallerThan shown: CGSize? = nil) async {
        guard let media, media.items.indices.contains(position), let target else { return }
        let requested = target
        let counter = media.items.count > 1 ? "\(position + 1)/\(media.items.count)" : nil

        switch media.items[position] {
        case .image(let candidates):
            let image = await loader.load(candidates, page: target.page, maxPixelSize: Self.maxPixelSize())
            guard let image, !Task.isCancelled, self.target == requested else { return }
            let enlargement = AppSettings.shared.minimumEnlargement
            if let shown, image.pixelSize.width <= shown.width * enlargement, image.pixelSize.height <= shown.height * enlargement { return }
            playback.stop()
            panel.show(image, counter: counter, anchor: requested.anchor)
            log.info("preview \(position + 1)/\(media.items.count): \(image.url.absoluteString, privacy: .public)")

        case .video(let url, let reportedSize):
            // Keyed by source and position, so the same video resumes however it was reached.
            let key = "\(requested.source)#\(position)"
            guard let size = await playback.start(url, key: key), !Task.isCancelled, self.target == requested,
                  let player = playback.player else { return }
            panel.show(player, videoSize: reportedSize ?? size, counter: counter, anchor: requested.anchor)
            log.info("preview \(position + 1)/\(media.items.count): video \(url.absoluteString, privacy: .public)")

        case .embed(let embed):
            guard let view = embeds.view(for: embed) else { return }
            playback.stop()
            panel.show(view, size: embed.size, counter: counter, anchor: requested.anchor)
            log.info("preview \(position + 1)/\(media.items.count): embed \(String(describing: embed), privacy: .public)")
            logPlaybackState(of: view, after: .seconds(5))
        }
        index = position
        scrollTap.isEnabled = media.items.count > 1
        prefetch(position + 1)
    }

    /// Embeds give no load or error callbacks we can use, so record whether media is actually playing.
    private func logPlaybackState(of view: WKWebView, after delay: Duration) {
        Task {
            try? await Task.sleep(for: delay)
            let state = await view.requestMediaPlaybackState()
            let name = switch state {
            case .playing: "playing"
            case .paused: "paused"
            case .suspended: "suspended"
            default: "no media"
            }
            log.info("embed media after \(delay, privacy: .public): \(name, privacy: .public)")
        }
    }

    /// Warms the loader's cache so stepping forward to an image is instant.
    private func prefetch(_ position: Int) {
        guard let media, media.items.indices.contains(position), case .image(let candidates) = media.items[position] else { return }
        let page = target?.page
        Task { [loader] in _ = await loader.load(candidates, page: page, maxPixelSize: Self.maxPixelSize()) }
    }

    /// Longest screen edge in pixels; larger images are downsampled to this when decoded.
    private static func maxPixelSize() -> Int {
        Int(NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 4096)
    }
}

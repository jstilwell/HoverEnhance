import AppKit
import WebKit

/// Decides when to show a preview for what the cursor is resting on, and when to hide it.
@MainActor
final class PreviewController {
    var isEnabled = true {
        didSet { if !isEnabled { reset() } }
    }

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
    /// While a video is showing, the cursor may move onto the panel to use its controls.
    private var isShowingVideo = false

    private struct Target: Equatable {
        let source: MediaSource
        /// The hovered element in global top-left-origin coordinates; leaving it hides the preview.
        let area: CGRect
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
        guard isEnabled else { return }
        guard let source = MediaResolver.source(for: info), let cursor = CGEvent(source: nil)?.location else {
            reset(because: "nothing to preview")
            return
        }
        // Still on the same thing: it's loading, showing, or was dismissed by a click.
        if target?.source == source { return }

        reset(because: "new target")
        let elementFrame = info.imageFrame ?? info.frame
        let newTarget = Target(
            source: source,
            area: elementFrame?.insetBy(dx: -4, dy: -4) ?? CGRect(origin: cursor, size: .zero).insetBy(dx: -24, dy: -24),
            page: info.pageURL
        )
        target = newTarget
        task = Task {
            guard let media = await fetcher.media(for: source), !Task.isCancelled, target == newTarget else { return }
            self.media = media
            // A lone image isn't worth showing unless it's meaningfully bigger than it already appears.
            await display(0, unlessSmallerThan: media.items.count == 1 ? elementFrame?.size : nil)
        }
    }

    func mouseMoved(to point: CGPoint) {
        guard let target else { return }
        var area = target.area
        // The bounding box of element and video covers the gap between them, so the cursor can cross over.
        if isShowingVideo, let panelFrame = panel.globalFrame { area = area.union(panelFrame) }
        if !area.contains(point) { reset(because: "cursor left") }
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
        playback.stop()
        embeds.suspend()
        isShowingVideo = false
        scrollTap.isEnabled = false
        panel.hide()
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
            if let shown, image.pixelSize.width <= shown.width * 1.2, image.pixelSize.height <= shown.height * 1.2 { return }
            playback.stop()
            isShowingVideo = false
            panel.show(image, counter: counter)
            log.info("preview \(position + 1)/\(media.items.count): \(image.url.absoluteString, privacy: .public)")

        case .video(let url, let reportedSize):
            // Keyed by source and position, so the same video resumes however it was reached.
            let key = "\(requested.source)#\(position)"
            guard let size = await playback.start(url, key: key), !Task.isCancelled, self.target == requested,
                  let player = playback.player else { return }
            isShowingVideo = true
            panel.show(player, videoSize: reportedSize ?? size, counter: counter)
            log.info("preview \(position + 1)/\(media.items.count): video \(url.absoluteString, privacy: .public)")

        case .embed(let embed):
            guard let view = embeds.view(for: embed) else { return }
            playback.stop()
            isShowingVideo = true
            panel.show(view, size: embed.size, counter: counter)
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

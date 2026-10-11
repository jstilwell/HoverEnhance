import AppKit

/// Decides when to show a preview for what the cursor is resting on, and when to hide it.
@MainActor
final class ImagePreviewController {
    var isEnabled = true {
        didSet { if !isEnabled { reset() } }
    }

    private let fetcher = MediaFetcher()
    private let loader = ImageLoader()
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
        /// The hovered element in global top-left-origin coordinates; leaving it hides the preview.
        let area: CGRect
        let page: URL?
    }

    init() {
        scrollTap.onStep = { [weak self] step in self?.step(by: step) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }

    func hovered(_ info: HoverInfo) {
        guard isEnabled else { return }
        guard let source = MediaResolver.source(for: info), let cursor = CGEvent(source: nil)?.location else {
            reset()
            return
        }
        // Still on the same thing: it's loading, showing, or was dismissed by a click.
        if target?.source == source { return }

        reset()
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
        if let target, !target.area.contains(point) { reset() }
    }

    /// Content moved under the cursor. While an album is up, the scroll tap has the wheel instead.
    func scrolled() {
        if !scrollTap.isEnabled { reset() }
    }

    /// Hides the preview but remembers the target, so it stays hidden until the cursor moves on.
    func dismiss() {
        task?.cancel()
        scrollTap.isEnabled = false
        panel.hide()
    }

    func reset() {
        task?.cancel()
        task = nil
        target = nil
        media = nil
        index = 0
        scrollTap.isEnabled = false
        panel.hide()
    }

    private func step(by delta: Int) {
        guard let media, media.items.count > 1 else { return }
        let next = min(max(index + delta, 0), media.items.count - 1)
        guard next != index else { return }
        // Move the index now so quick scrolls add up, even before the image arrives.
        index = next
        task?.cancel()
        task = Task { await display(next) }
    }

    private func display(_ position: Int, unlessSmallerThan shown: CGSize? = nil) async {
        guard let media, media.items.indices.contains(position), let target else { return }
        let requested = target
        switch media.items[position] {
        case .image(let candidates):
            let image = await loader.load(candidates, page: target.page, maxPixelSize: Self.maxPixelSize())
            guard let image, !Task.isCancelled, self.target == requested else { return }
            if let shown, image.pixelSize.width <= shown.width * 1.2, image.pixelSize.height <= shown.height * 1.2 { return }
            index = position
            let isAlbum = media.items.count > 1
            log.info("preview \(position + 1)/\(media.items.count): \(image.url.absoluteString, privacy: .public)")
            panel.show(image, counter: isAlbum ? "\(position + 1)/\(media.items.count)" : nil)
            scrollTap.isEnabled = isAlbum
            prefetch(position + 1)
        }
    }

    /// Warms the loader's cache so stepping forward is instant.
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

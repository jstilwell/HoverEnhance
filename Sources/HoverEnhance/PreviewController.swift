import AppKit
import SwiftUI
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
    /// The item on screen, which decides what the scroll wheel does.
    private var showing: MediaItem?
    private var albumSteps = StepAccumulator()
    /// When the scroll wheel last acted on the preview; those scrolls never reach the page.
    private var lastScrollHandled = Date.distantPast

    private struct Target: Equatable {
        let source: MediaSource
        /// Where the cursor rested, in global top-left-origin coordinates. The preview hangs off it.
        let anchor: CGPoint
        /// The notch under the cursor. Leaving it any way but onto the preview ends the hover.
        let notch: CGRect
        /// The hovered element, for zooming into the part of an image the cursor is on.
        let element: CGRect?
        /// The hovered app's bundle ID; creator cards subscribe through it in browser mode.
        let app: String?
        let page: URL?
    }

    init() {
        scrollTap.handler = { [weak self] input in self?.scroll(input) ?? false }
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
        let newTarget = Target(source: source, anchor: cursor, notch: panel.notchFrame(at: cursor), element: elementFrame, app: info.bundleID, page: info.pageURL)
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
        guard let target else { return }
        if panel.isOnPreview(point) {
            panel.pan(toward: point)
        } else if !target.notch.contains(point) && !panel.covers(point) {
            reset(because: "left the notch")
        }
    }

    /// Content moved under the cursor. Scrolls the preview took never get here, but in case the
    /// system reports them anyway, recent ones are ignored.
    func scrolled() {
        if Date().timeIntervalSince(lastScrollHandled) > 0.3 { reset(because: "scrolled") }
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
        showing = nil
        albumSteps.reset()
        playback.stop()
        embeds.suspend()
    }

    /// The scroll wheel with the cursor on the notch or the preview acts on the preview. Returns
    /// whether it did, in which case the page underneath doesn't scroll.
    private func scroll(_ input: ScrollInput) -> Bool {
        guard let target, let media, let showing,
              target.notch.contains(input.location) || panel.covers(input.location) else { return false }
        let handled = act(on: input, showing: showing, isAlbum: media.items.count > 1)
        if handled { lastScrollHandled = Date() }
        return handled
    }

    private func act(on input: ScrollInput, showing: MediaItem, isAlbum: Bool) -> Bool {
        let settings = AppSettings.shared
        if isAlbum {
            // Momentum is swallowed but ignored, so a flick doesn't race through the album.
            guard !input.isMomentum else { return true }
            let steps = albumSteps.steps(input.forward, precise: input.isPrecise)
            if steps != 0 { step(by: steps) }
            return true
        }
        switch showing {
        case .image:
            guard settings.imageScroll == .zoom else { return false }
            guard !input.isMomentum, input.up != 0 else { return true }
            panel.zoom(by: input.isPrecise ? exp(input.up * 0.01) : (input.up > 0 ? 1.25 : 0.8))
        case .video:
            guard !input.isMomentum else { return true }
            let readout = switch settings.videoScroll {
            case .scrub:
                // A wheel notch is 5 seconds; trackpad travel is a tenth of a second per point.
                input.forward == 0 ? nil : playback.scrub(by: input.isPrecise ? input.forward * 0.1 : (input.forward > 0 ? 5 : -5))
            case .volume:
                input.up == 0 ? nil : playback.changeVolume(by: input.isPrecise ? input.up * 0.005 : (input.up > 0 ? 0.05 : -0.05))
            }
            if let readout { panel.flash(readout) }
        case .embed, .channel:
            // On the player or card, scrolling belongs to it; on the notch, it mustn't move the page away.
            return !panel.isOnPreview(input.location)
        }
        return true
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
            panel.show(image, counter: counter, anchor: requested.anchor, focus: Self.focus(of: requested.anchor, in: requested.element))
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

        case .channel(let channel):
            let card = NSHostingView(rootView: CreatorCardView(channel: channel, browser: requested.app))
            card.appearance = NSAppearance(named: .darkAqua)
            playback.stop()
            panel.show(card, counter: counter, anchor: requested.anchor)
            log.info("preview: creator card for \(channel.title, privacy: .public)")
        }
        index = position
        showing = media.items[position]
        scrollTap.isEnabled = true
        prefetch(position + 1)
    }

    /// Where the cursor rests on the thumbnail, as fractions from its top left: the part of the
    /// full image to zoom in on.
    private static func focus(of anchor: CGPoint, in element: CGRect?) -> CGPoint {
        guard let element, element.width > 0, element.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(max((anchor.x - element.minX) / element.width, 0), 1),
                       y: min(max((anchor.y - element.minY) / element.height, 0), 1))
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

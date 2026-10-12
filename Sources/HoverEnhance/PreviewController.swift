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
    private var spaceObserver: NSObjectProtocol?

    private var target: Target?
    private var media: Media?
    /// The album position being shown, or being loaded after a scroll.
    private var index = 0
    private var task: Task<Void, Never>?
    /// Whether the current load failed, as opposed to finding nothing worth showing.
    private var loadFailed = false
    /// The album image being fetched ahead, so showing it waits for that download instead of starting another.
    private var prefetching: (position: Int, task: Task<Void, Never>)?
    /// The item on screen, which decides what the scroll wheel does.
    private var showing: MediaItem?
    private var albumSteps = StepAccumulator()
    /// The play button of a song in a large Finder preview.
    private var audioModel: AudioPreviewModel?
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
        let page: URL?
    }

    init() {
        scrollTap.handler = { [weak self] input in self?.scroll(input) ?? false }
        playback.onVolumeChange = { [weak self] level, muted in self?.panel.updateVolume(level: level, muted: muted) }
        playback.onPlayingChange = { [weak self] playing in self?.audioModel?.isPlaying = playing }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset(because: "app switched") }
        }
        // The preview shows on every Space, so it would stay over whatever the new one shows.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset(because: "space switched") }
        }
    }

    /// `again` is a second look at the spot the cursor stopped on, after the page had a moment to fill
    /// in: it can start a preview, or switch to a better one still loading, but never ends one.
    func hovered(_ info: HoverInfo, again: Bool = false) {
        guard let cursor = CGEvent(source: nil)?.location else { return }
        // Resting on the preview or its notch: what's underneath doesn't count.
        if target != nil, panel.covers(cursor) { return }
        func noPreview(because reason: String) {
            if !again { reset(because: reason) }
        }
        let settings = AppSettings.shared
        guard settings.previewsEnabled, settings.previewsAllowed(holding: NSEvent.modifierFlags),
              !settings.isExcluded(info.bundleID), !settings.skips(page: info.pageURL) else {
            noPreview(because: "previews are off here")
            return
        }
        guard let source = MediaResolver.source(for: info), settings.filter.allows(source) else {
            noPreview(because: "nothing to preview")
            return
        }
        let keyHeld = NSEvent.modifierFlags.contains(settings.activationKey.flag)
        guard settings.otherApps.allows(source, in: info.appKind, keyHeld: keyHeld) else {
            noPreview(because: "not previewed outside browsers")
            return
        }
        // An image the page already shows about as large as a preview could be has nothing to add,
        // unless it's from a post with more to step through.
        let shownLarge = info.imageFrame.map {
            !PreviewGeometry.couldEnlarge(shown: $0.size, room: panel.room(at: cursor), by: settings.minimumEnlargement)
        } ?? false
        if shownLarge, !source.isPost {
            noPreview(because: "already shown large")
            return
        }
        // Still on the same thing: it's loading, showing, or was dismissed by a click.
        if target?.source == source { return }
        // A second look doesn't replace what's already on screen.
        if again, showing != nil { return }

        reset(because: "new target")
        let elementFrame = info.imageFrame ?? info.frame
        let newTarget = Target(source: source, anchor: cursor, notch: panel.notchFrame(at: cursor), element: elementFrame, page: info.pageURL)
        target = newTarget
        // File cards wait longer on purpose; the spinner counts only time past that. A post shown large
        // may turn out to hold nothing more, so it gets no spinner.
        var spinnerDelay: Duration? = shownLarge ? nil : .milliseconds(300)
        if case .file = source, let delay = spinnerDelay {
            spinnerDelay = delay + .milliseconds(max(settings.finderDelay - settings.hoverDelay, 0))
        }
        task = Task {
            loadFailed = false
            let shown = await withLoadingIndicator(after: spinnerDelay, for: newTarget) {
                guard let fetched = await fetcher.media(for: source) else {
                    loadFailed = true
                    return false
                }
                guard let media = AppSettings.shared.filter.apply(to: fetched),
                      !Task.isCancelled, target == newTarget, !shownLarge || media.items.count > 1 else { return false }
                self.media = media
                // An album opens at the photo the page shows, as in a carousel stepped partway through.
                let start = info.imageURL.flatMap(media.index(showing:)) ?? 0
                // A lone image isn't worth showing unless it's meaningfully bigger than it already appears.
                return await display(start, unlessSmallerThan: media.items.count == 1 ? elementFrame?.size : nil)
            }
            // Nothing to show after all: take the spinner down, after saying why if the load failed.
            guard !shown, target == newTarget, !Task.isCancelled else { return }
            if loadFailed, panel.isShowingLoading {
                panel.showFailure(anchor: newTarget.anchor)
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, target == newTarget, showing == nil else { return }
            }
            panel.hide()
        }
    }

    /// Runs `load`, with a spinner in place of the preview if nothing has appeared after `delay`.
    private func withLoadingIndicator(after delay: Duration?, for target: Target, _ load: () async -> Bool) async -> Bool {
        guard let delay else { return await load() }
        let indicator = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.target == target, showing == nil else { return }
            panel.showLoading(anchor: target.anchor)
        }
        defer { indicator.cancel() }
        return await load()
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

    /// Esc closes any preview. Any other key press in Finder (Space for Quick Look, Return to rename,
    /// typing to find a file) means the card is in the way. Either way it stays closed until the cursor
    /// moves to something else.
    func keyPressed(isEscape: Bool) {
        if isEscape {
            dismiss()
            return
        }
        guard case .file = target?.source, AppSettings.shared.finderClosesOnKeyPress else { return }
        dismiss()
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
        prefetching?.task.cancel()
        prefetching = nil
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
        audioModel = nil
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
            // On the video itself, and on the notch and the volume rocker beside it, as set for each.
            switch panel.isOnPreview(input.location) ? settings.videoScroll : settings.notchVideoScroll {
            case .scrub:
                if input.forward != 0, let position = playback.scrub(by: input.scrubSeconds(perStep: Double(settings.videoScrubSeconds))) {
                    panel.flash(position)
                }
            case .volume:
                // The rocker shows the new level.
                if input.up != 0 { playback.changeVolume(by: input.isPrecise ? input.up * 0.005 : (input.up > 0 ? 0.05 : -0.05)) }
            }
        case .embed, .channel:
            // On the player or card, scrolling belongs to it; on the notch, it mustn't move the page away.
            return !panel.isOnPreview(input.location)
        case .file:
            // Finder scrolls as usual, which closes the card.
            return false
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

    /// Shows the item at `position`, once it has loaded. Returns whether it did. `allowingLarge` loads an
    /// image of any size, after the user asked for one over the limit.
    @discardableResult
    private func display(_ position: Int, unlessSmallerThan shown: CGSize? = nil, allowingLarge: Bool = false) async -> Bool {
        guard let media, media.items.indices.contains(position), let target else { return false }
        let requested = target
        let counter = media.items.count > 1 ? "\(position + 1)/\(media.items.count)" : nil
        let settings = AppSettings.shared
        /// What the scroll wheel should take the item for, when not what it is: a Finder video plays.
        var shownAs: MediaItem?

        switch media.items[position] {
        case .image(let candidates):
            if !allowingLarge, let ahead = prefetching, ahead.position == position { await ahead.task.value }
            let outcome = await loader.load(candidates, page: target.page, maxPixelSize: Self.maxPixelSize(),
                                            byteLimit: allowingLarge ? ImageLoader.largestEver : settings.largestImageBytes)
            guard !Task.isCancelled, self.target == requested else { return false }
            switch outcome {
            case .loaded(let image):
                // Compared as the preview would show it: no larger than the room beside the cursor.
                if let shown, !PreviewGeometry.enlarges(image.pixelSize, shown: shown, room: panel.room(at: requested.anchor),
                                                        by: settings.minimumEnlargement) {
                    return false
                }
                playback.stop()
                panel.show(image, counter: counter, anchor: requested.anchor, focus: Self.focus(of: requested.anchor, in: requested.element))
                log.infoPrivateInRelease("preview \(position + 1)/\(media.items.count): \(image.url.absoluteString)")
            case .tooLarge(let url, let bytes):
                let card = NSHostingView(rootView: TooLargeCardView(url: url, bytes: bytes, limit: settings.largestImageBytes) { [weak self] in
                    await self?.loadAnyway(position) ?? false
                })
                playback.stop()
                panel.show(card, counter: counter, anchor: requested.anchor)
                log.infoPrivateInRelease("preview \(position + 1)/\(media.items.count): over the size limit, \(url.absoluteString)")
            case .failed:
                loadFailed = true
                return false
            }

        case .video(let url, let reportedSize):
            // Keyed by source and position, so the same video resumes however it was reached.
            let key = "\(requested.source)#\(position)"
            guard let size = await playback.start(url, key: key) else {
                loadFailed = true
                return false
            }
            guard !Task.isCancelled, self.target == requested, let player = playback.player else { return false }
            panel.show(player, videoSize: reportedSize ?? size, counter: counter, anchor: requested.anchor)
            if let volume = playback.volume { panel.showVolume(level: volume.level, muted: volume.muted) }
            log.infoPrivateInRelease("preview \(position + 1)/\(media.items.count): video \(url.absoluteString)")

        case .embed(let embed):
            guard let view = embeds.view(for: embed) else { return false }
            playback.stop()
            panel.show(view, size: embed.size, counter: counter, anchor: requested.anchor)
            log.infoPrivateInRelease("preview \(position + 1)/\(media.items.count): embed \(String(describing: embed))")
            logPlaybackState(of: view, after: .seconds(5))

        case .channel(let channel):
            let card = NSHostingView(rootView: CreatorCardView(channel: channel))
            playback.stop()
            panel.show(card, counter: counter, anchor: requested.anchor)
            log.infoPrivateInRelease("preview: creator card for \(channel.title)")

        case .file(let url):
            // Cards wait longer than other previews, so sweeping across a folder doesn't flash them.
            let extraWait = settings.finderDelay - settings.hoverDelay
            if extraWait > 0 { try? await Task.sleep(for: .milliseconds(extraWait)) }
            guard !Task.isCancelled, self.target == requested else { return false }
            let options = settings.fileCard
            var details = await Task.detached { FileDetails.load(url, options: options) }.value
            // What audio and video files say in their own tags, which Spotlight may not have indexed.
            await details.addMedia(from: url, options: options, forPreview: settings.finderMediaPreviews)
            guard !Task.isCancelled, self.target == requested else { return false }
            let card = FileCard(url: url, details: details, options: options)
            if settings.finderMediaPreviews, let kind = FileMediaKind(details: details),
               let large = await showLarge(kind, url: url, card: card, details: details, counter: counter, target: requested) {
                shownAs = large
                log.infoPrivateInRelease("preview: large \(String(describing: kind)) for \(url.path(percentEncoded: false))")
                break
            }
            guard !Task.isCancelled, self.target == requested else { return false }
            let view = CardHostingView(rootView: FileCardView(card: card))
            // The list of apps using the file fills in after the card appears.
            view.onSizeChange = { [weak self, weak view] in
                // SwiftUI is in the middle of layout here; refit once it's done.
                Task { @MainActor in if let self, let view { self.panel.refit(view) } }
            }
            playback.stop()
            panel.show(view, counter: counter, anchor: requested.anchor)
            log.infoPrivateInRelease("preview: file card for \(url.path(percentEncoded: false))")
        }
        index = position
        showing = shownAs ?? media.items[position]
        scrollTap.isEnabled = true
        prefetch(position + 1)
        return true
    }

    /// A Finder image, video, or audio file large, with its card beside or below it, whichever leaves the
    /// media larger. Returns what the scroll wheel should take it for, or nil to show the plain card,
    /// as when there isn't room for the media to be worth it.
    private func showLarge(_ kind: FileMediaKind, url: URL, card: FileCard, details: FileDetails, counter: String?,
                           target requested: Target) async -> MediaItem? {
        // Measured on a card of its own, so the one shown doesn't start loading before it's on screen.
        let measure = FileCard(url: url, details: details, options: card.options)
        let detailsSize = NSHostingView(rootView: FileCardView(card: measure, showsImage: false, width: FileMediaCardView.detailsWidth)).fittingSize
        let room = panel.room(at: requested.anchor)
        let natural: CGSize
        switch kind {
        case .image:
            guard let size = await Task.detached(operation: { LocalImage.pixelSize(of: url) }).value else { return nil }
            natural = size
        case .video:
            guard let size = await playback.start(url, key: Self.playbackKey(url)) else { return nil }
            // Small videos are hard to watch at 1:1, as on the web.
            let scale = max(1, 720 / max(size.width, size.height))
            natural = CGSize(width: size.width * scale, height: size.height * scale)
        case .audio:
            natural = FileMediaCardView.artworkSize
        }
        guard !Task.isCancelled, target == requested else { return nil }
        let (layout, mediaSize) = FileMediaLayout.choose(media: natural, details: detailsSize, room: room)
        guard mediaSize.width >= 120, mediaSize.height >= 90 else {
            playback.stop()
            return nil
        }

        let content: FileMediaCardView.Content
        switch kind {
        case .image:
            let scale = ScreenSpace.screen(containing: requested.anchor)?.backingScaleFactor ?? 2
            let pixels = Int(max(mediaSize.width, mediaSize.height) * scale)
            guard let image = await Task.detached(operation: { LocalImage.load(url, maxPixelSize: pixels) }).value,
                  !Task.isCancelled, target == requested else { return nil }
            content = .image(image)
        case .video:
            guard let player = playback.player else { return nil }
            content = .video(player)
        case .audio:
            let model = AudioPreviewModel { [weak self] in self?.toggleAudio(url) }
            audioModel = model
            content = .audio(artwork: details.media?.artwork.flatMap(NSImage.init(data:)), model: model)
        }
        let view = CardHostingView(rootView: FileMediaCardView(card: card, content: content, layout: layout, mediaSize: mediaSize))
        // The list of apps using the file fills in after the card appears.
        view.onSizeChange = { [weak self, weak view] in
            Task { @MainActor in if let self, let view { self.panel.refit(view) } }
        }
        if kind != .video { playback.stop() }
        panel.show(view, counter: counter, anchor: requested.anchor)

        switch kind {
        case .video:
            if let volume = playback.volume { panel.showVolume(level: volume.level, muted: volume.muted) }
            return .video(url, size: nil)
        case .audio where AppSettings.shared.finderAutoplayAudio:
            return await startAudio(url) ? .video(url, size: nil) : .file(url)
        case .audio, .image:
            return .file(url)
        }
    }

    /// The play button of a song in a large preview: starts it, or pauses and resumes it.
    private func toggleAudio(_ url: URL) {
        if let player = playback.player {
            if player.timeControlStatus == .paused { player.play() } else { player.pause() }
            return
        }
        Task {
            // Now it plays, the scroll wheel acts on it as on a video.
            if await startAudio(url) { showing = .video(url, size: nil) }
        }
    }

    /// Plays a song in a large preview, with the volume rocker beside the notch. Returns whether it started.
    private func startAudio(_ url: URL) async -> Bool {
        guard await playback.start(url, key: Self.playbackKey(url), audioOnly: true) != nil, let volume = playback.volume else { return false }
        panel.showVolume(level: volume.level, muted: volume.muted)
        return true
    }

    /// Finder files resume where they left off, like videos online.
    private static func playbackKey(_ url: URL) -> String {
        "file:" + url.path(percentEncoded: false)
    }

    /// The too-large card's Load Anyway: loads the image at `position` whatever its size.
    private func loadAnyway(_ position: Int) async -> Bool {
        task?.cancel()
        // Kept as the current task, so moving on cancels it like any other load.
        return await withCheckedContinuation { continuation in
            task = Task { continuation.resume(returning: await display(position, allowingLarge: true)) }
        }
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

    /// Warms the loader's cache so stepping forward to an image is instant. It ends with the hover.
    private func prefetch(_ position: Int) {
        guard prefetching?.position != position else { return }
        prefetching?.task.cancel()
        prefetching = nil
        guard let media, media.items.indices.contains(position), case .image(let candidates) = media.items[position] else { return }
        let page = target?.page
        let limit = AppSettings.shared.largestImageBytes
        let task = Task { [loader] in _ = await loader.load(candidates, page: page, maxPixelSize: Self.maxPixelSize(), byteLimit: limit) }
        prefetching = (position, task)
    }

    /// Longest screen edge in pixels; larger images are downsampled to this when decoded.
    private static func maxPixelSize() -> Int {
        Int(NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 4096)
    }
}

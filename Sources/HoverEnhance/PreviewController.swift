import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
    private let shortcutTap = ShortcutTap()
    /// The image on screen, for copying and saving it.
    private var shownImage: LoadedImage?
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
    /// The controls under a song or video in a large Finder preview.
    private var transport: MediaTransport?
    /// When the scroll wheel last acted on the preview; those scrolls never reach the page.
    private var lastScrollHandled = Date.distantPast
    /// A menu bar item clicked opens its own menu, and its popup stays away until that closes.
    private var menuBarClicks = MenuBarClicks()

    private struct Target: Equatable {
        let source: MediaSource
        /// Where the cursor rested, in global top-left-origin coordinates. The preview hangs off it.
        let anchor: CGPoint
        /// The notch under the cursor. Leaving it any way but onto the preview ends the hover.
        let notch: CGRect
        /// The hovered element, for zooming into the part of an image the cursor is on.
        let element: CGRect?
        let page: URL?
        /// For a menu bar item: its frame, which the preview hangs under.
        var item: CGRect?
    }

    init() {
        scrollTap.handler = { [weak self] input in self?.scroll(input) ?? false }
        shortcutTap.shortcuts = { AppSettings.shared.previewShortcuts }
        panel.onBarAction = { [weak self] action in self?.perform(action) }
        shortcutTap.handler = { [weak self] shortcut, isRepeat in self?.perform(shortcut, isRepeat: isRepeat) ?? false }
        playback.onVolumeChange = { [weak self] level, muted in self?.panel.updateVolume(level: level, muted: muted) }
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
              !settings.isExcluded(info.bundleID), !settings.skips(page: info.websiteURL) else {
            noPreview(because: "previews are off here")
            return
        }
        guard let source = MediaResolver.source(for: info, cards: settings.filter.cards), settings.filter.allows(source) else {
            noPreview(because: "nothing to preview")
            return
        }
        let keyHeld = NSEvent.modifierFlags.contains(settings.activationKey.flag)
        guard settings.otherApps.allows(source, in: info.appKind, keyHeld: keyHeld) else {
            noPreview(because: "not previewed outside browsers")
            return
        }
        // An image the page already shows about as large as a preview could be has nothing to add,
        // unless it's from a post with more to step through. A Letterboxd card is about the poster's film,
        // whatever its size.
        let isLetterboxdCard = if case .letterboxd = source { true } else { false }
        let shownLarge = !isLetterboxdCard && info.imageFrame.map {
            !PreviewGeometry.couldEnlarge(shown: $0.size, room: panel.room(at: cursor), by: settings.minimumEnlargement)
        } ?? false
        if shownLarge, !source.isPost {
            noPreview(because: "already shown large")
            return
        }
        let item = source.menuBarItem.map { Self.itemFrame($0, cursor: cursor) }
        if let item, menuBarClicks.menuIsOpen(for: item) {
            noPreview(because: "its menu is open")
            return
        }
        // Still on the same thing: it's loading, showing, or was dismissed by a click.
        if target?.source == source { return }
        // A second look doesn't replace what's already on screen, unless that's an image the link it
        // has just found around it outranks.
        if again, showing != nil, !(target.map { source.replaces(onSecondLook: $0.source) } ?? false) { return }

        reset(because: "new target")
        let elementFrame = info.imageFrame ?? info.frame
        let notch = item.map { panel.dropDownHoverArea(at: cursor, item: $0) } ?? panel.notchFrame(at: cursor)
        let newTarget = Target(source: source, anchor: cursor, notch: notch, element: elementFrame, page: info.pageURL, item: item)
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
                let lookup = await fetcher.lookUp(source)
                guard case .found(let fetched) = lookup else {
                    // A cancelled load mustn't mark the next one failed.
                    if lookup == .failed, !Task.isCancelled { loadFailed = true }
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
            panel.showLoading(anchor: target.anchor, item: target.item)
        }
        defer { indicator.cancel() }
        return await load()
    }

    /// A menu bar item's frame, if it's where the cursor is: on a second display's menu bar it may be
    /// reported on the main one's, and then a stand-in around the cursor will do.
    static func itemFrame(_ frame: CGRect, cursor: CGPoint) -> CGRect {
        frame.insetBy(dx: -4, dy: -4).contains(cursor) ? frame : CGRect(x: cursor.x - 16, y: cursor.y - 12, width: 32, height: 24)
    }

    /// Ends the hover the moment the cursor leaves the notch, unless it moves onto the preview.
    func mouseMoved(to point: CGPoint) {
        guard let target else { return }
        if panel.isOnPreview(point) {
            panel.pan(toward: point)
        } else if !target.notch.contains(point) && !panel.covers(point) {
            reset(because: "left the notch")
            return
        }
        panel.updateActionBar(cursor: point)
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
            // Esc closes a menu bar item's menu too.
            menuBarClicks.closed()
            dismiss()
            return
        }
        guard case .file = target?.source, AppSettings.shared.finderClosesOnKeyPress else { return }
        dismiss()
    }

    /// A click hides the preview. On a menu bar item, it also opens the item's menu, which keeps the popup away.
    func clicked(at point: CGPoint?) {
        if let point { menuBarClicks.clicked(at: point, on: target?.item) }
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
        shortcutTap.isEnabled = false
        showing = nil
        shownImage = nil
        transport?.detach()
        transport = nil
        albumSteps.reset()
        playback.stop()
        embeds.suspend()
    }

    /// What copying and saving can do with `item`: an image or a video from the web is copied and saved,
    /// and a card's link copied. Finder's own copy works on its files.
    private static func actions(for item: MediaItem) -> Set<PreviewShortcut> {
        switch item {
        case .image: [.copy, .save, .saveAs]
        case .video(let url, _): url.isFileURL ? [] : [.copy, .save, .saveAs]
        case .article, .github, .letterboxd: [.copy]
        case .embed, .channel, .file, .weather, .network: []
        }
    }

    /// For an image or video from the web, which get the copy and save buttons: whether it can be saved.
    private static func barCanSave(_ item: MediaItem) -> Bool? {
        switch item {
        case .image: true
        case .video(let url, _): url.isFileURL ? nil : PreviewActions.canSave(video: url)
        default: nil
        }
    }

    /// A copy or save shortcut, or a button under the preview. Returns whether it acted, in which case the
    /// app under the preview never sees the keys.
    @discardableResult
    private func perform(_ action: PreviewShortcut, isRepeat: Bool = false) -> Bool {
        guard let showing, let target, Self.actions(for: showing).contains(action) else { return false }
        if isRepeat { return true }
        let page = target.page
        let settings = AppSettings.shared
        switch (action, showing) {
        case (.copy, .image):
            guard let image = shownImage else { return false }
            Task {
                let data = await loader.original(of: image.url, page: page)
                PreviewActions.copy(image: data, fallback: image.image)
                if self.target == target { panel.flash("Copied") }
            }
        case (.save, .image), (.saveAs, .image):
            guard let image = shownImage else { return false }
            Task {
                guard let data = await loader.original(of: image.url, page: page) else {
                    if self.target == target { panel.flash("Couldn't save") }
                    return
                }
                let type = PreviewActions.imageType(of: data)
                if action == .saveAs {
                    chooseFile(for: image.url, type: type) { file in
                        _ = PreviewActions.save(data, from: image.url, page: page, type: type, to: .file(file))
                    }
                } else {
                    let folder = settings.saveFolderInUse
                    let saved = PreviewActions.save(data, from: image.url, page: page, type: type, to: .folder(folder))
                    if self.target == target { panel.flash(saved == nil ? "Couldn't save" : "Saved to \(Self.name(of: folder))") }
                }
            }
        case (.copy, .video(let url, _)):
            PreviewActions.copy(link: url)
            panel.flash("Copied address")
        case (.save, .video(let url, _)), (.saveAs, .video(let url, _)):
            guard PreviewActions.canSave(video: url) else {
                panel.flash("Streamed videos can't be saved")
                return true
            }
            if action == .saveAs {
                chooseFile(for: url, type: PreviewActions.videoType(mimeType: nil, url: url)) { file in
                    Task { _ = await PreviewActions.save(video: url, page: page, to: .file(file)) }
                }
            } else {
                let folder = settings.saveFolderInUse
                panel.flash("Saving…")
                // The download goes on if the preview closes; Downloads in the Dock bounces when it's done there.
                Task {
                    let saved = await PreviewActions.save(video: url, page: page, to: .folder(folder))
                    if self.target == target { panel.flash(saved == nil ? "Couldn't save" : "Saved to \(Self.name(of: folder))") }
                }
            }
        case (.copy, .article(let article)):
            PreviewActions.copy(link: article.url)
            panel.flash("Copied link")
        case (.copy, .github(let card)):
            PreviewActions.copy(link: card.url)
            panel.flash("Copied link")
        case (.copy, .letterboxd(let card)):
            PreviewActions.copy(link: card.url)
            panel.flash("Copied link")
        default:
            return false
        }
        return true
    }

    /// Save As: asks where, starting in the save folder, then calls `save` with the file chosen. The
    /// panel brings HoverEnhance forward, which ends the preview, and the app that was in front comes
    /// back once it's done.
    private func chooseFile(for url: URL, type: UTType?, then save: @escaping @MainActor (URL) -> Void) {
        let previous = NSWorkspace.shared.frontmostApplication
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = PreviewActions.fileName(for: url, type: type)
        savePanel.directoryURL = AppSettings.shared.saveFolderInUse
        savePanel.canCreateDirectories = true
        if let type { savePanel.allowedContentTypes = [type] }
        NSApp.activate()
        savePanel.begin { response in
            MainActor.assumeIsolated {
                if response == .OK, let file = savePanel.url { save(file) }
                previous?.activate()
            }
        }
    }

    /// "Downloads", as Finder names the folder.
    private static func name(of folder: URL) -> String {
        FileManager.default.displayName(atPath: folder.path(percentEncoded: false))
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
        case .embed, .channel, .article, .github, .letterboxd, .weather, .network:
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
                shownImage = image
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
                if !Task.isCancelled { loadFailed = true }
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

        case .weather(let item):
            let model = WeatherPopupModel(settings: settings)
            await model.load()
            guard !Task.isCancelled, self.target == requested else { return false }
            let view = CardHostingView(rootView: WeatherPopupView(
                model: model,
                useCurrentLocation: {
                    AppSettings.shared.weatherLocation = .current
                    Task { await model.use(.current) }
                },
                openSettings: { NotificationCenter.default.post(name: .showSettingsTab, object: SettingsTab.weather) },
                retry: { Task { await model.retry() } }
            ))
            // A newer forecast, or a retry, changes its size.
            view.onSizeChange = { [weak self, weak view] in
                Task { @MainActor in if let self, let view { self.panel.refit(view) } }
            }
            playback.stop()
            panel.show(view, counter: nil, anchor: requested.anchor, item: item)
            log.info("preview: weather")

        case .network(let item):
            let model = NetworkPopupModel(settings: settings)
            await model.load()
            guard !Task.isCancelled, self.target == requested else { return false }
            let view = CardHostingView(rootView: NetworkPopupView(
                model: model,
                openSettings: { NotificationCenter.default.post(name: .showSettingsTab, object: SettingsTab.macOS) }
            ))
            // Wi-Fi joining or leaving, or the public address arriving, changes its size.
            view.onSizeChange = { [weak self, weak view] in
                Task { @MainActor in if let self, let view { self.panel.refit(view) } }
            }
            playback.stop()
            panel.show(view, counter: nil, anchor: requested.anchor, item: item)
            log.info("preview: network")

        case .channel(let channel, let video):
            let card = NSHostingView(rootView: CreatorCardView(channel: channel, video: video))
            playback.stop()
            panel.show(card, counter: counter, anchor: requested.anchor)
            log.infoPrivateInRelease("preview: creator card for \(channel.title)")

        case .article(let article):
            let card = NSHostingView(rootView: WikipediaCardView(article: article))
            playback.stop()
            panel.show(card, counter: counter, anchor: requested.anchor)
            log.infoPrivateInRelease("preview: article card for \(article.url.absoluteString)")

        case .github(let github):
            let card = NSHostingView(rootView: GitHubCardView(card: github))
            playback.stop()
            panel.show(card, counter: counter, anchor: requested.anchor)
            log.infoPrivateInRelease("preview: GitHub card for \(github.url.absoluteString)")

        case .letterboxd(let letterboxd):
            let card = CardHostingView(rootView: LetterboxdCardView(card: letterboxd))
            // Showing a review's spoilers changes its size.
            card.onSizeChange = { [weak self, weak card] in
                Task { @MainActor in if let self, let card { self.panel.refit(card) } }
            }
            playback.stop()
            panel.show(card, counter: counter, anchor: requested.anchor)
            log.infoPrivateInRelease("preview: Letterboxd card for \(letterboxd.url.absoluteString)")

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
        if case .image = media.items[position] {} else { shownImage = nil }
        scrollTap.isEnabled = true
        shortcutTap.isEnabled = !(showing.map(Self.actions) ?? []).isEmpty
        // Images and videos from the web get buttons too; a card's link is copied with the key alone.
        // An image over the size limit shows Load Anyway instead, with nothing to copy yet.
        let isImageCard = if case .image = showing, shownImage == nil { true } else { false }
        panel.offerActions(canSave: isImageCard ? nil : showing.flatMap(Self.barCanSave), shortcuts: settings.previewShortcuts)
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
        let (layout, mediaSize) = FileMediaLayout.choose(media: natural, details: detailsSize, room: room,
                                                         controls: kind == .image ? 0 : TransportBar.height)
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
            let transport = MediaTransport(duration: details.media?.duration ?? details.duration)
            transport.loadDuration(of: url)
            transport.attach(player)
            self.transport = transport
            content = .video(player, transport)
        case .audio:
            // Tags can hold artwork of any size; it's decoded off the main thread at the size shown, with
            // the same limits as images from the web. Twice the side covers art that isn't square, as it
            // fills the square.
            let scale = ScreenSpace.screen(containing: requested.anchor)?.backingScaleFactor ?? 2
            let pixels = Int(max(mediaSize.width, mediaSize.height) * scale) * 2
            let artwork = await Task.detached { [data = details.media?.artwork] in
                data.flatMap { ImageDecoder.decode($0, from: url, maxPixelSize: pixels)?.image }
            }.value
            guard !Task.isCancelled, target == requested else { return nil }
            let transport = MediaTransport(duration: details.media?.duration ?? details.duration) { [weak self] in self?.playAudio(url) }
            transport.loadDuration(of: url)
            self.transport = transport
            content = .audio(artwork: artwork, transport: transport)
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

    /// The play button of a song in a large preview that isn't playing yet. Once it is, its controls
    /// work its player directly.
    private func playAudio(_ url: URL) {
        Task {
            // Now it plays, the scroll wheel acts on it as on a video.
            if await startAudio(url) { showing = .video(url, size: nil) }
        }
    }

    /// Plays a song in a large preview, with the volume rocker beside the notch. Returns whether it started.
    private func startAudio(_ url: URL) async -> Bool {
        guard await playback.start(url, key: Self.playbackKey(url), audioOnly: true) != nil, let player = playback.player,
              let volume = playback.volume else { return false }
        transport?.attach(player)
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

import AVKit
import AppKit
import SwiftUI
import WebKit

/// A floating panel that shows media beside the cursor, joined to it by a small notch under the
/// cursor. Images and the notch are click-through; videos take the mouse so their playback controls
/// work. Both use the system's popover material, so they follow light and dark mode.
@MainActor
final class PreviewPanel {
    private let panel = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    private let container = NSVisualEffectView()
    /// Clips a zoomed image to the preview.
    private let imageClip = NSView()
    private let imageView = NSImageView()
    private let playerView = AVPlayerView()
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    /// Briefly shows what the scroll wheel just did: zoom, volume, or position.
    private let readout = NSView()
    private let readoutLabel = NSTextField(labelWithString: "")
    private var readoutGeneration = 0
    /// Stands in for the preview while it loads.
    private let spinner = NSProgressIndicator()
    private let loadingView = NSView()
    /// Bumped whenever the panel is shown or hidden, so a fade-out that's overtaken doesn't hide it.
    private var visibility = 0
    /// Fading out: a card that changes size then mustn't bring the panel back.
    private var isHiding = false
    private var content: NSView?
    /// The card on screen: its size and where it was shown, for refitting it.
    private var card: (size: CGSize, counter: String?, anchor: CGPoint, item: CGRect?)?
    private var zoom: CGFloat = 1
    /// The point of the image that stays put while zooming, as fractions of it from the top left.
    private var focus = CGPoint(x: 0.5, y: 0.5)
    private let maximumZoom: CGFloat = 8
    /// Click-through, so the link under the cursor can still be clicked.
    private let notch = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    private let notchView = NSVisualEffectView()
    /// The volume during a video, beside the notch. Click-through, like the notch.
    private let rocker = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    private let rockerView = VolumeRockerView(frame: .zero)
    /// The content the rocker belongs to; showing anything else takes it away.
    private weak var rockerOwner: NSView?
    /// The rocker and the space between it and the notch, in global top-left-origin coordinates.
    private var rockerReach: CGRect?
    /// Where the preview on screen was shown from, for placing the rocker.
    private var placement: (anchor: CGPoint, placeRight: Bool)?

    private let padding = PreviewGeometry.padding
    private let screenMargin: CGFloat = 8
    static let cornerRadius: CGFloat = 12

    init() {
        for window in [panel, notch, rocker] {
            window.level = .statusBar
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        }
        panel.hasShadow = true

        for view in [container, notchView] {
            view.material = .popover
            view.blendingMode = .behindWindow
            // The panels are never key; without this they'd draw the flat inactive look.
            view.state = .active
            view.wantsLayer = true
            view.layer?.masksToBounds = true
        }
        notchView.layer?.cornerRadius = 7
        notch.contentView = notchView
        rocker.contentView = rockerView
        container.layer?.cornerRadius = Self.cornerRadius
        panel.contentView = container

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.sizeToFit()
        spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        loadingView.addSubview(spinner)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageClip.wantsLayer = true
        imageClip.layer?.masksToBounds = true
        imageClip.addSubview(imageView)

        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = false
        playerView.allowsPictureInPicturePlayback = false

        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(white: 0, alpha: 0.65).cgColor
        badge.layer?.cornerRadius = 6
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        badgeLabel.textColor = .white
        badge.addSubview(badgeLabel)
        container.addSubview(badge)

        readout.wantsLayer = true
        readout.layer?.backgroundColor = NSColor(white: 0, alpha: 0.65).cgColor
        readout.layer?.cornerRadius = 8
        readout.isHidden = true
        readoutLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        readoutLabel.textColor = .white
        readout.addSubview(readoutLabel)
        container.addSubview(readout)
    }

    /// Whether a global top-left-origin point is on the preview, its notch, or the volume rocker.
    func covers(_ point: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        return ScreenSpace.flip(panel.frame).contains(point) || ScreenSpace.flip(notch.frame).contains(point)
            || (rocker.isVisible && rockerReach?.contains(point) == true)
    }

    /// Shows the volume rocker beside the notch, for the video on screen.
    func showVolume(level: Float, muted: Bool) {
        guard panel.isVisible, let content, let placement else { return }
        rockerOwner = content
        rockerView.level = level
        rockerView.isMuted = muted
        placeRocker(anchor: placement.anchor, placeRight: placement.placeRight)
        rocker.alphaValue = panel.alphaValue
        rocker.orderFrontRegardless()
        if panel.alphaValue < 1 { fade(to: 1) }
    }

    /// Moves the rocker's level, as the player's volume changes.
    func updateVolume(level: Float, muted: Bool) {
        guard rocker.isVisible else { return }
        rockerView.level = level
        rockerView.isMuted = muted
    }

    private func placeRocker(anchor: CGPoint, placeRight: Bool) {
        let frame = PreviewGeometry.rockerFrame(anchor: anchor, placeRight: placeRight, visible: visibleFrame(at: anchor))
        rocker.setFrame(ScreenSpace.flip(frame), display: true)
        rockerReach = PreviewGeometry.rockerReach(rocker: frame, notch: PreviewGeometry.notchFrame(anchor: anchor, placeRight: placeRight))
    }

    private func hideRocker() {
        rocker.orderOut(nil)
        rockerOwner = nil
        rockerReach = nil
    }

    /// Whether a global top-left-origin point is on the preview itself.
    func isOnPreview(_ point: CGPoint) -> Bool {
        panel.isVisible && ScreenSpace.flip(panel.frame).contains(point)
    }

    /// The most a preview's content can measure beside the cursor at `anchor`.
    func room(at anchor: CGPoint) -> CGSize {
        PreviewGeometry.room(anchor: anchor, visible: visibleFrame(at: anchor), maxFraction: CGFloat(AppSettings.shared.maximumSize))
    }

    /// Whether the spinner is what's on screen.
    var isShowingLoading: Bool { panel.isVisible && content === loadingView }

    /// In place of the spinner, when what it waited for couldn't be loaded.
    func showFailure(anchor: CGPoint) {
        let view = NSHostingView(rootView: LoadFailedView())
        present(view, naturalSize: view.fittingSize, counter: nil, interactive: false, anchor: anchor)
    }

    /// A small spinner where the preview will appear, joined to the cursor by the notch, while it loads.
    /// `item` is a menu bar item's frame, for a preview that hangs under it.
    func showLoading(anchor: CGPoint, item: CGRect? = nil) {
        let size = CGSize(width: 20, height: 20)
        loadingView.frame.size = size
        spinner.setFrameOrigin(CGPoint(x: (size.width - spinner.frame.width) / 2, y: (size.height - spinner.frame.height) / 2))
        spinner.startAnimation(nil)
        present(loadingView, naturalSize: size, counter: nil, interactive: false, anchor: anchor, item: item)
    }

    /// Where the cursor can go without ending the hover of a menu bar item at `item`, besides the
    /// preview itself: the item, and the tab down to the preview.
    func dropDownHoverArea(at anchor: CGPoint, item: CGRect) -> CGRect {
        let top = max(item.maxY, visibleFrame(at: anchor).minY) + PreviewGeometry.dropGap
        return PreviewGeometry.dropDownHoverArea(anchor: anchor, item: item, panelTop: top)
    }

    /// The notch a preview for a cursor at `anchor` (global, top-left origin) will have, for use
    /// before the preview has loaded.
    func notchFrame(at anchor: CGPoint) -> CGRect {
        PreviewGeometry.notchFrame(anchor: anchor, placeRight: PreviewGeometry.placesRight(anchor: anchor, visible: visibleFrame(at: anchor)))
    }

    /// `anchor` is where the cursor rested, in global top-left-origin coordinates. `counter` is the
    /// "2/5" album position, or nil for a single item. `focus` is the part of the image to zoom in
    /// on, as fractions from its top left.
    func show(_ image: LoadedImage, counter: String?, anchor: CGPoint, focus: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        playerView.player = nil
        imageView.image = image.image
        zoom = 1
        self.focus = focus
        present(imageClip, naturalSize: image.pixelSize, counter: counter, interactive: false, anchor: anchor)
        layoutImage()
    }

    /// Zooms a shown image in (factor > 1) or out, keeping the focus point in place.
    func zoom(by factor: CGFloat) {
        guard content === imageClip, panel.isVisible else { return }
        zoom = min(max(zoom * factor, 1), maximumZoom)
        layoutImage()
        flash("\(Int((zoom * 100).rounded()))%")
    }

    /// Over a zoomed image, the part shown follows the cursor, like a loupe.
    func pan(toward point: CGPoint) {
        guard content === imageClip, zoom > 1, panel.isVisible else { return }
        let area = ScreenSpace.flip(panel.frame).insetBy(dx: padding, dy: padding)
        focus = CGPoint(x: min(max((point.x - area.minX) / area.width, 0), 1),
                        y: min(max((point.y - area.minY) / area.height, 0), 1))
        layoutImage()
    }

    /// Shows `text` over the bottom of the preview for a moment.
    func flash(_ text: String) {
        readoutLabel.stringValue = text
        readoutLabel.sizeToFit()
        let size = CGSize(width: readoutLabel.frame.width + 20, height: readoutLabel.frame.height + 10)
        readout.frame = CGRect(x: (container.bounds.width - size.width) / 2, y: padding + 14, width: size.width, height: size.height)
        readoutLabel.setFrameOrigin(CGPoint(x: 10, y: 5))
        readout.isHidden = false
        readout.alphaValue = 1
        readoutGeneration += 1
        let generation = readoutGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, generation == readoutGeneration else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; readout.animator().alphaValue = 0 }, completionHandler: nil)
        }
    }

    private func layoutImage() {
        imageView.frame = PreviewGeometry.zoomedImageFrame(in: imageClip.bounds, zoom: zoom, focus: focus)
    }

    func show(_ player: AVPlayer, videoSize: CGSize, counter: String?, anchor: CGPoint) {
        imageView.image = nil
        playerView.player = player
        // Small videos are hard to watch at 1:1, so bring the long edge up to at least 720 points.
        let scale = max(1, 720 / max(videoSize.width, videoSize.height))
        present(playerView, naturalSize: CGSize(width: videoSize.width * scale, height: videoSize.height * scale),
                counter: counter, interactive: true, anchor: anchor)
    }

    /// A site's own player; it takes the mouse for its controls.
    func show(_ webView: WKWebView, size: CGSize, counter: String?, anchor: CGPoint) {
        imageView.image = nil
        playerView.player = nil
        present(webView, naturalSize: size, counter: counter, interactive: true, anchor: anchor)
    }

    /// Any interactive view, at its own fitting size; used for cards. `item` is a menu bar item's
    /// frame, for a card that hangs under it.
    func show(_ view: NSView, counter: String?, anchor: CGPoint, item: CGRect? = nil) {
        imageView.image = nil
        playerView.player = nil
        card = (view.fittingSize, counter, anchor, item)
        present(view, naturalSize: view.fittingSize, counter: counter, interactive: true, anchor: anchor, item: item)
    }

    /// Resizes a card on screen whose content changed size, such as a list that filled in.
    func refit(_ view: NSView) {
        guard content === view, panel.isVisible, !isHiding, let card else { return }
        let size = view.fittingSize
        // Setting the frame can make SwiftUI ask again; an unchanged size ends it there.
        guard abs(size.width - card.size.width) > 0.5 || abs(size.height - card.size.height) > 0.5 else { return }
        self.card?.size = size
        present(view, naturalSize: size, counter: card.counter, interactive: true, anchor: card.anchor, item: card.item)
    }

    /// Fades the preview out. What it showed is let go once it's gone, unless it's shown again first.
    func hide() {
        guard panel.isVisible || notch.isVisible else { return }
        visibility += 1
        isHiding = true
        let generation = visibility
        // Nothing on a fading panel should take a click.
        panel.ignoresMouseEvents = true
        fade(to: 0) { [weak self] in
            guard let self, generation == visibility else { return }
            panel.orderOut(nil)
            notch.orderOut(nil)
            hideRocker()
            spinner.stopAnimation(nil)
            imageView.image = nil
            playerView.player = nil
            // A card's SwiftUI tree, or a paused player's web view, isn't kept by a hidden panel.
            content?.removeFromSuperview()
            content = nil
        }
    }

    /// Fades both windows, or sets them at once when the system asks for reduced motion.
    private func fade(to alpha: CGFloat, then completion: (@MainActor () -> Void)? = nil) {
        let windows = [panel, notch] + (rocker.isVisible ? [rocker] : [])
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            windows.forEach { $0.alphaValue = alpha }
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = alpha > 0 ? 0.12 : 0.1
            windows.forEach { $0.animator().alphaValue = alpha }
        }, completionHandler: {
            MainActor.assumeIsolated { completion?() }
        })
    }

    private func visibleFrame(at point: CGPoint) -> CGRect {
        guard let screen = ScreenSpace.screen(containing: point) else { return .zero }
        return ScreenSpace.flip(screen.visibleFrame).insetBy(dx: screenMargin, dy: screenMargin)
    }

    /// Beside the cursor, or under the menu bar item at `item`.
    private func present(_ view: NSView, naturalSize: CGSize, counter: String?, interactive: Bool, anchor: CGPoint, item: CGRect? = nil) {
        let visible = visibleFrame(at: anchor)
        if let item {
            guard let frame = PreviewGeometry.dropDownFrame(anchor: anchor, item: item, naturalSize: naturalSize, visible: visible) else { return }
            panel.setFrame(ScreenSpace.flip(frame), display: false)
            placement = nil
            notch.setFrame(ScreenSpace.flip(PreviewGeometry.dropDownNotchFrame(anchor: anchor, item: item, panelTop: frame.minY)), display: false)
            if rocker.isVisible { hideRocker() }
            // The tab hangs from the menu bar: its top end is rounded, its bottom meets the preview. (Layer
            // corners count from the bottom.)
            notchView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else {
            let maxFraction = CGFloat(AppSettings.shared.maximumSize)
            guard let frame = PreviewGeometry.panelFrame(anchor: anchor, naturalSize: naturalSize, visible: visible, maxFraction: maxFraction) else { return }
            panel.setFrame(ScreenSpace.flip(frame), display: false)

            let placeRight = frame.minX > anchor.x
            placement = (anchor, placeRight)
            notch.setFrame(ScreenSpace.flip(PreviewGeometry.notchFrame(anchor: anchor, placeRight: placeRight)), display: false)
            // The rocker stays with the video it belongs to, as when its card is refitted, and goes otherwise.
            if view === rockerOwner {
                placeRocker(anchor: anchor, placeRight: placeRight)
            } else if rocker.isVisible {
                hideRocker()
            }
            // Round only the end under the cursor; the other end meets the preview.
            notchView.layer?.maskedCorners = placeRight
                ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
                : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
        // Hidden or not, the notch still decides when the hover ends.
        notchView.isHidden = !AppSettings.shared.showsNotch

        if content !== view {
            if content === loadingView { spinner.stopAnimation(nil) }
            content?.removeFromSuperview()
            container.addSubview(view, positioned: .below, relativeTo: badge)
            content = view
        }
        view.frame = container.bounds.insetBy(dx: padding, dy: padding)
        readout.isHidden = true
        layoutBadge(counter)
        panel.ignoresMouseEvents = !interactive

        visibility += 1
        isHiding = false
        let appearing = !panel.isVisible
        if appearing {
            panel.alphaValue = 0
            notch.alphaValue = 0
        }
        notch.orderFrontRegardless()
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        // Fades in when new, and back in if it was fading out.
        if appearing || panel.alphaValue < 1 { fade(to: 1) }
    }

    private func layoutBadge(_ text: String?) {
        badge.isHidden = text == nil
        guard let text else { return }
        badgeLabel.stringValue = text
        badgeLabel.sizeToFit()
        let inset = CGSize(width: 8, height: 3)
        let size = CGSize(width: badgeLabel.frame.width + 2 * inset.width, height: badgeLabel.frame.height + 2 * inset.height)
        // Top left; the container isn't flipped, so "top" is maxY.
        badge.frame = CGRect(x: padding + 8, y: container.bounds.maxY - padding - 8 - size.height, width: size.width, height: size.height)
        badgeLabel.setFrameOrigin(CGPoint(x: inset.width, y: inset.height))
    }
}

/// Hosts a SwiftUI card and reports when its content wants a different size, so the panel can refit it.
final class CardHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (@MainActor () -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}

/// What replaces the spinner, for a moment, when the preview couldn't be loaded.
private struct LoadFailedView: View {
    var body: some View {
        Label("Couldn't load a preview", systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

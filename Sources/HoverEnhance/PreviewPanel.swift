import AVKit
import AppKit
import SwiftUI
import WebKit

/// A floating panel that shows media beside the cursor, joined to it by a small notch under the
/// cursor. Images and the notch are click-through; videos take the mouse so their playback controls
/// work.
@MainActor
final class PreviewPanel {
    private let panel = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    private let container = NSView()
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
    private var content: NSView?
    /// The card on screen: its size and where it was shown, for refitting it.
    private var card: (size: CGSize, counter: String?, anchor: CGPoint)?
    private var zoom: CGFloat = 1
    /// The point of the image that stays put while zooming, as fractions of it from the top left.
    private var focus = CGPoint(x: 0.5, y: 0.5)
    private let maximumZoom: CGFloat = 8
    /// Click-through, so the link under the cursor can still be clicked.
    private let notch = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    private let notchView = NSView()

    private let padding = PreviewGeometry.padding
    private let screenMargin: CGFloat = 8
    private static let background = NSColor(white: 0.12, alpha: 1)

    init() {
        for window in [panel, notch] {
            window.level = .statusBar
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        }
        panel.hasShadow = true

        notchView.wantsLayer = true
        notchView.layer?.backgroundColor = Self.background.withAlphaComponent(0.85).cgColor
        notchView.layer?.cornerRadius = 6
        notch.contentView = notchView

        container.wantsLayer = true
        container.layer?.backgroundColor = Self.background.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        panel.contentView = container

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

    /// Whether a global top-left-origin point is on the preview or its notch.
    func covers(_ point: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        return ScreenSpace.flip(panel.frame).contains(point) || ScreenSpace.flip(notch.frame).contains(point)
    }

    /// Whether a global top-left-origin point is on the preview itself.
    func isOnPreview(_ point: CGPoint) -> Bool {
        panel.isVisible && ScreenSpace.flip(panel.frame).contains(point)
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

    /// Any interactive view, at its own fitting size; used for cards.
    func show(_ view: NSView, counter: String?, anchor: CGPoint) {
        imageView.image = nil
        playerView.player = nil
        card = (view.fittingSize, counter, anchor)
        present(view, naturalSize: view.fittingSize, counter: counter, interactive: true, anchor: anchor)
    }

    /// Resizes a card on screen whose content changed size, such as a list that filled in.
    func refit(_ view: NSView) {
        guard content === view, panel.isVisible, let card else { return }
        let size = view.fittingSize
        // Setting the frame can make SwiftUI ask again; an unchanged size ends it there.
        guard abs(size.width - card.size.width) > 0.5 || abs(size.height - card.size.height) > 0.5 else { return }
        self.card?.size = size
        present(view, naturalSize: size, counter: card.counter, interactive: true, anchor: card.anchor)
    }

    func hide() {
        panel.orderOut(nil)
        notch.orderOut(nil)
        imageView.image = nil
        playerView.player = nil
    }

    private func visibleFrame(at point: CGPoint) -> CGRect {
        guard let screen = ScreenSpace.screen(containing: point) else { return .zero }
        return ScreenSpace.flip(screen.visibleFrame).insetBy(dx: screenMargin, dy: screenMargin)
    }

    private func present(_ view: NSView, naturalSize: CGSize, counter: String?, interactive: Bool, anchor: CGPoint) {
        let maxFraction = CGFloat(AppSettings.shared.maximumSize)
        guard let frame = PreviewGeometry.panelFrame(anchor: anchor, naturalSize: naturalSize, visible: visibleFrame(at: anchor),
                                                     maxFraction: maxFraction) else { return }
        panel.setFrame(ScreenSpace.flip(frame), display: false)

        let placeRight = frame.minX > anchor.x
        notch.setFrame(ScreenSpace.flip(PreviewGeometry.notchFrame(anchor: anchor, placeRight: placeRight)), display: false)
        // Hidden or not, the notch still decides when the hover ends.
        notch.alphaValue = AppSettings.shared.showsNotch ? 1 : 0
        // Round only the end under the cursor; the other end meets the preview.
        notchView.layer?.maskedCorners = placeRight
            ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]

        if content !== view {
            content?.removeFromSuperview()
            container.addSubview(view, positioned: .below, relativeTo: badge)
            content = view
        }
        view.frame = container.bounds.insetBy(dx: padding, dy: padding)
        readout.isHidden = true
        layoutBadge(counter)
        panel.ignoresMouseEvents = !interactive

        notch.orderFrontRegardless()
        panel.orderFrontRegardless()
        panel.invalidateShadow()
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

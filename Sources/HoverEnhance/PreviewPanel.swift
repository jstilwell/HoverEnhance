import AVKit
import AppKit
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
    private let imageView = NSImageView()
    private let playerView = AVPlayerView()
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var content: NSView?
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
    }

    /// Whether a global top-left-origin point is on the preview or its notch.
    func covers(_ point: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        return ScreenSpace.flip(panel.frame).contains(point) || ScreenSpace.flip(notch.frame).contains(point)
    }

    /// The notch a preview for a cursor at `anchor` (global, top-left origin) will have, for use
    /// before the preview has loaded.
    func notchFrame(at anchor: CGPoint) -> CGRect {
        PreviewGeometry.notchFrame(anchor: anchor, placeRight: PreviewGeometry.placesRight(anchor: anchor, visible: visibleFrame(at: anchor)))
    }

    /// `anchor` is where the cursor rested, in global top-left-origin coordinates. `counter` is the
    /// "2/5" album position, or nil for a single item.
    func show(_ image: LoadedImage, counter: String?, anchor: CGPoint) {
        playerView.player = nil
        imageView.image = image.image
        present(imageView, naturalSize: image.pixelSize, counter: counter, interactive: false, anchor: anchor)
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

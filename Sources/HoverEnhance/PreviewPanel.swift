import AppKit

/// A click-through floating panel that shows media beside the cursor.
@MainActor
final class PreviewPanel {
    private let panel = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    private let container = NSView()
    private let imageView = NSImageView()
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var content: NSView?

    private let padding: CGFloat = 4
    /// Space between the cursor and the panel, so the panel never sits under the cursor.
    private let gap: CGFloat = 20
    private let screenMargin: CGFloat = 8

    init() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        panel.contentView = container

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true

        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(white: 0, alpha: 0.65).cgColor
        badge.layer?.cornerRadius = 6
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        badgeLabel.textColor = .white
        badge.addSubview(badgeLabel)
        container.addSubview(badge)
    }

    /// `counter` is the "2/5" album position, or nil for a single item.
    func show(_ image: LoadedImage, counter: String?) {
        imageView.image = image.image
        present(imageView, naturalSize: image.pixelSize, counter: counter)
    }

    func hide() {
        panel.orderOut(nil)
        imageView.image = nil
    }

    /// Shows `view` at one pixel per point (like a browser at 100% zoom), scaled down to fit beside
    /// the cursor on whichever side has more room.
    private func present(_ view: NSView, naturalSize: CGSize, counter: String?) {
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }) ?? NSScreen.main,
              naturalSize.width > 0, naturalSize.height > 0 else { return }

        let visible = screen.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let roomRight = visible.maxX - (cursor.x + gap)
        let roomLeft = (cursor.x - gap) - visible.minX
        let placeRight = roomRight >= roomLeft
        let room = CGSize(width: max(roomRight, roomLeft) - 2 * padding, height: visible.height - 2 * padding)
        let scale = min(1, room.width / naturalSize.width, room.height / naturalSize.height)
        guard scale > 0 else { return }

        let size = CGSize(
            width: (naturalSize.width * scale).rounded() + 2 * padding,
            height: (naturalSize.height * scale).rounded() + 2 * padding
        )
        let x = placeRight ? cursor.x + gap : cursor.x - gap - size.width
        let y = min(max(cursor.y - size.height / 2, visible.minY), visible.maxY - size.height)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)

        if content !== view {
            content?.removeFromSuperview()
            container.addSubview(view, positioned: .below, relativeTo: badge)
            content = view
        }
        view.frame = container.bounds.insetBy(dx: padding, dy: padding)
        layoutBadge(counter)

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

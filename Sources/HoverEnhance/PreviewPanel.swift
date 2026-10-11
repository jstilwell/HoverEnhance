import AppKit

/// A click-through floating panel that shows an image beside the cursor.
@MainActor
final class PreviewPanel {
    private let panel = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    private let imageView = NSImageView()

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

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        panel.contentView = container
    }

    /// Shows the image at one image pixel per point (like a browser at 100% zoom), scaled down to
    /// fit beside the cursor on whichever side has more room.
    func show(_ image: LoadedImage) {
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }) ?? NSScreen.main,
              image.pixelSize.width > 0, image.pixelSize.height > 0 else { return }

        let visible = screen.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let roomRight = visible.maxX - (cursor.x + gap)
        let roomLeft = (cursor.x - gap) - visible.minX
        let placeRight = roomRight >= roomLeft
        let room = CGSize(width: max(roomRight, roomLeft) - 2 * padding, height: visible.height - 2 * padding)
        let scale = min(1, room.width / image.pixelSize.width, room.height / image.pixelSize.height)
        guard scale > 0 else { return }

        let size = CGSize(
            width: (image.pixelSize.width * scale).rounded() + 2 * padding,
            height: (image.pixelSize.height * scale).rounded() + 2 * padding
        )
        let x = placeRight ? cursor.x + gap : cursor.x - gap - size.width
        let y = min(max(cursor.y - size.height / 2, visible.minY), visible.maxY - size.height)

        imageView.image = image.image
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        imageView.frame = panel.contentView!.bounds.insetBy(dx: padding, dy: padding)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
        imageView.image = nil
    }
}

import AppKit

/// A small click-through panel in the corner of the screen showing the latest hover result, or news
/// with no preview up to say it on.
@MainActor
final class HUD {
    /// For news: previews paused by their shortcut, a save that ended after its preview closed.
    static let toast = HUD(font: .systemFont(ofSize: 13, weight: .medium))
    private var flashes = 0

    private let panel = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    private let background = NSVisualEffectView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init(font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)) {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        label.font = font
        label.isSelectable = false
        label.lineBreakMode = .byCharWrapping
        label.preferredMaxLayoutWidth = 520
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
        ])
        panel.contentView = background
    }

    func show(_ text: String) {
        label.stringValue = text
        background.layoutSubtreeIfNeeded()
        let size = background.fittingSize

        // Bottom-right of whichever screen the cursor is on, clear of the Dock.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.minY + 16)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// Shows `text` for a moment.
    func flash(_ text: String) {
        show(text)
        flashes += 1
        let mine = flashes
        Task {
            try? await Task.sleep(for: .seconds(2))
            if flashes == mine { hide() }
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

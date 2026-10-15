import AppKit

/// Where a preview and its notch go for a cursor position, in global top-left-origin coordinates
/// (the space `CGEvent` and the Accessibility API use).
enum PreviewGeometry {
    static let padding: CGFloat = 4
    /// Space between the cursor and the preview, so the preview never sits under the cursor. The
    /// notch bridges it.
    static let gap: CGFloat = 20
    /// How far the notch reaches past the cursor, away from the preview.
    static let notchReach: CGFloat = 14
    static let notchHeight: CGFloat = 28

    /// The preview goes on whichever side of the cursor has more room.
    static func placesRight(anchor: CGPoint, visible: CGRect) -> Bool {
        visible.maxX - anchor.x >= anchor.x - visible.minX
    }

    /// The preview at one pixel per point (like a browser at 100% zoom), scaled down to fit beside
    /// the cursor and centered on it vertically as far as the screen allows. `maxFraction` limits it
    /// to that share of the room.
    static func panelFrame(anchor: CGPoint, naturalSize: CGSize, visible: CGRect, maxFraction: CGFloat = 1) -> CGRect? {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return nil }
        let placeRight = placesRight(anchor: anchor, visible: visible)
        let room = room(anchor: anchor, visible: visible, maxFraction: maxFraction)
        let scale = min(1, room.width / naturalSize.width, room.height / naturalSize.height)
        guard scale > 0 else { return nil }

        let size = CGSize(
            width: (naturalSize.width * scale).rounded() + 2 * padding,
            height: (naturalSize.height * scale).rounded() + 2 * padding
        )
        let x = placeRight ? anchor.x + gap : anchor.x - gap - size.width
        let y = min(max(anchor.y - size.height / 2, visible.minY), visible.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The most a preview's content can measure beside the cursor at `anchor`, inside its padding.
    static func room(anchor: CGPoint, visible: CGRect, maxFraction: CGFloat = 1) -> CGSize {
        let sideRoom = placesRight(anchor: anchor, visible: visible) ? visible.maxX - (anchor.x + gap) : (anchor.x - gap) - visible.minX
        return CGSize(width: sideRoom * maxFraction - 2 * padding, height: visible.height * maxFraction - 2 * padding)
    }

    /// Whether a preview of an image `natural` pixels in size, fitted into `room`, would be wider or
    /// taller than the page shows it (`shown`) by more than `enlargement`.
    static func enlarges(_ natural: CGSize, shown: CGSize, room: CGSize, by enlargement: Double) -> Bool {
        let scale = min(1, room.width / natural.width, room.height / natural.height)
        return natural.width * scale > shown.width * enlargement || natural.height * scale > shown.height * enlargement
    }

    /// Whether any preview of an image the page shows at `shown` could be larger by more than
    /// `enlargement`, before knowing the image's own size: none can when the page shows it about as
    /// large as `room` allows for its shape.
    static func couldEnlarge(shown: CGSize, room: CGSize, by enlargement: Double) -> Bool {
        guard shown.width > 0, shown.height > 0 else { return true }
        return min(room.width / shown.width, room.height / shown.height) > enlargement
    }

    /// Where to put an image zoomed by `zoom` inside `bounds` (AppKit view coordinates, origin bottom
    /// left) so the point at `focus` (fractions of the image from its top left) stays at the same
    /// place in the frame. The image's edges never pull inside the frame.
    static func zoomedImageFrame(in bounds: CGRect, zoom: CGFloat, focus: CGPoint) -> CGRect {
        let size = CGSize(width: bounds.width * zoom, height: bounds.height * zoom)
        return CGRect(
            x: bounds.minX + (bounds.width - size.width) * focus.x,
            y: bounds.minY + (bounds.height - size.height) * (1 - focus.y),
            width: size.width, height: size.height
        )
    }

    // MARK: - Under a menu bar item

    /// Space between the menu bar and a preview hanging under it.
    static let dropGap: CGFloat = 6

    /// A preview for a menu bar item (`item`, the item's frame): under the menu bar, centered on the
    /// cursor as far as the screen allows, at its natural size or scaled down to fit.
    static func dropDownFrame(anchor: CGPoint, item: CGRect, naturalSize: CGSize, visible: CGRect) -> CGRect? {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return nil }
        let top = max(item.maxY, visible.minY) + dropGap
        let room = CGSize(width: visible.width - 2 * padding, height: visible.maxY - top - 2 * padding)
        let scale = min(1, room.width / naturalSize.width, room.height / naturalSize.height)
        guard scale > 0 else { return nil }
        let size = CGSize(width: (naturalSize.width * scale).rounded() + 2 * padding,
                          height: (naturalSize.height * scale).rounded() + 2 * padding)
        let x = min(max(anchor.x - size.width / 2, visible.minX), visible.maxX - size.width)
        return CGRect(x: x, y: top, width: size.width, height: size.height)
    }

    /// The tab that joins a menu bar item to the preview under it: from the item's bottom edge to the
    /// preview's top, under the cursor.
    static func dropDownNotchFrame(anchor: CGPoint, item: CGRect, panelTop: CGFloat) -> CGRect {
        let width = min(notchHeight, max(item.width, 1))
        let x = min(max(anchor.x - width / 2, item.minX), item.maxX - width)
        // A point into the preview, so there's no seam.
        return CGRect(x: x, y: item.maxY, width: width, height: max(panelTop - item.maxY, 0) + 1)
    }

    /// Where the cursor can go without ending the hover, besides the preview: the whole item, so moving
    /// across it doesn't, and the tab down to the preview.
    static func dropDownHoverArea(anchor: CGPoint, item: CGRect, panelTop: CGFloat) -> CGRect {
        item.union(dropDownNotchFrame(anchor: anchor, item: item, panelTop: panelTop))
    }

    /// A small tab under the cursor that reaches across the gap to the preview's edge. Leaving it
    /// any way but onto the preview ends the hover.
    static func notchFrame(anchor: CGPoint, placeRight: Bool) -> CGRect {
        let y = anchor.y - notchHeight / 2
        return placeRight
            ? CGRect(x: anchor.x - notchReach, y: y, width: notchReach + gap, height: notchHeight)
            : CGRect(x: anchor.x - gap, y: y, width: gap + notchReach, height: notchHeight)
    }
}

extension PreviewGeometry {
    static let rockerSize = CGSize(width: 18, height: 104)
    /// Between the rocker and the notch, and between the rocker and the preview's edge.
    static let rockerSpacing: CGFloat = 3

    /// The volume rocker shown during a video: above the notch against the preview's edge, or below
    /// the notch when there's no room above it.
    static func rockerFrame(anchor: CGPoint, placeRight: Bool, visible: CGRect) -> CGRect {
        let notch = notchFrame(anchor: anchor, placeRight: placeRight)
        let x = placeRight ? anchor.x + gap - rockerSpacing - rockerSize.width : anchor.x - gap + rockerSpacing
        let above = notch.minY - rockerSpacing - rockerSize.height
        let y = above >= visible.minY ? above : notch.maxY + rockerSpacing
        return CGRect(origin: CGPoint(x: x, y: y), size: rockerSize)
    }

    /// The rocker with the space between it and the notch, so the cursor can move from one to the
    /// other without ending the hover.
    static func rockerReach(rocker: CGRect, notch: CGRect) -> CGRect {
        rocker.union(CGRect(x: rocker.minX, y: notch.minY, width: rocker.width, height: notch.height))
    }
}

/// Where a Finder preview's details go: beside the image, video, or artwork, or below it.
enum FileMediaLayout: Equatable, Sendable {
    case beside, below

    /// Whichever leaves the media larger in `room`, with the media's size there. Media isn't enlarged
    /// past `media`, its natural size; details that don't fit beside it in height go below. `controls` is
    /// the height of a player's controls under the media.
    static func choose(media: CGSize, details: CGSize, room: CGSize, controls: CGFloat = 0) -> (layout: FileMediaLayout, mediaSize: CGSize) {
        func fit(_ box: CGSize) -> CGSize {
            let box = CGSize(width: box.width, height: box.height - controls)
            guard media.width > 0, media.height > 0, box.width > 0, box.height > 0 else { return .zero }
            let scale = min(1, box.width / media.width, box.height / media.height)
            return CGSize(width: (media.width * scale).rounded(.down), height: (media.height * scale).rounded(.down))
        }
        let beside = details.height <= room.height ? fit(CGSize(width: room.width - details.width, height: room.height)) : .zero
        let below = fit(CGSize(width: room.width, height: room.height - details.height))
        return beside.width * beside.height >= below.width * below.height ? (.beside, beside) : (.below, below)
    }
}

/// Converts between AppKit's screen space (origin at the bottom left of the primary display) and
/// the global top-left-origin space. The conversion is its own inverse.
enum ScreenSpace {
    static func flip(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The screen showing a global top-left-origin point.
    static func screen(containing point: CGPoint) -> NSScreen? {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitPoint = NSPoint(x: point.x, y: height - point.y)
        return NSScreen.screens.first { NSMouseInRect(appKitPoint, $0.frame, false) } ?? NSScreen.main
    }
}

/// Clicks on menu bar items. Clicking one opens its own menu, which its popup would cover, so the popup
/// stays away until the menu closes: on a click anywhere else, a second click on the item, or Esc.
struct MenuBarClicks: Equatable {
    /// The last click, until something closes the menu it may have opened.
    private var lastClick: CGPoint?
    /// The item whose menu is open, once known.
    private var openItem: CGRect?

    mutating func clicked(at point: CGPoint, on shownItem: CGRect? = nil) {
        // A second click on the item closes its menu.
        if let openItem, openItem.contains(point) {
            closed()
            return
        }
        lastClick = point
        openItem = shownItem.flatMap { $0.contains(point) ? $0 : nil }
    }

    /// Whether `item`'s menu is open: the last click was on it.
    mutating func menuIsOpen(for item: CGRect) -> Bool {
        guard let lastClick, item.contains(lastClick) else { return false }
        openItem = item
        return true
    }

    mutating func closed() {
        lastClick = nil
        openItem = nil
    }
}

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
        let sideRoom = placeRight ? visible.maxX - (anchor.x + gap) : (anchor.x - gap) - visible.minX
        let room = CGSize(width: sideRoom * maxFraction - 2 * padding, height: visible.height * maxFraction - 2 * padding)
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

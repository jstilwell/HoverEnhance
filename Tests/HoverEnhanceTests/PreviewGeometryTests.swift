import Foundation
import Testing
@testable import HoverEnhance

struct PreviewGeometryTests {
    /// A 1920×1080 screen, top-left origin.
    private let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func opensOnTheRoomierSide() {
        #expect(PreviewGeometry.placesRight(anchor: CGPoint(x: 400, y: 500), visible: visible))
        #expect(!PreviewGeometry.placesRight(anchor: CGPoint(x: 1500, y: 500), visible: visible))
    }

    @Test func notchJoinsTheCursorToThePreviewOnTheRight() throws {
        let anchor = CGPoint(x: 400, y: 500)
        let panel = try #require(PreviewGeometry.panelFrame(anchor: anchor, naturalSize: CGSize(width: 600, height: 400), visible: visible))
        let notch = PreviewGeometry.notchFrame(anchor: anchor, placeRight: true)
        #expect(panel == CGRect(x: 420, y: 296, width: 608, height: 408))
        #expect(notch.maxX == panel.minX)
        #expect(notch.contains(anchor))
        // Left, up, and down off the notch are outside it; right runs onto the preview.
        #expect(!notch.contains(CGPoint(x: anchor.x - 15, y: anchor.y)))
        #expect(!notch.contains(CGPoint(x: anchor.x, y: anchor.y - 15)))
        #expect(!notch.contains(CGPoint(x: anchor.x, y: anchor.y + 15)))
        #expect(notch.contains(CGPoint(x: anchor.x + 19, y: anchor.y)))
        #expect(panel.contains(CGPoint(x: anchor.x + 20, y: anchor.y)))
    }

    @Test func notchJoinsTheCursorToThePreviewOnTheLeft() throws {
        let anchor = CGPoint(x: 1500, y: 500)
        let panel = try #require(PreviewGeometry.panelFrame(anchor: anchor, naturalSize: CGSize(width: 600, height: 400), visible: visible))
        let notch = PreviewGeometry.notchFrame(anchor: anchor, placeRight: false)
        #expect(panel.maxX == anchor.x - PreviewGeometry.gap)
        #expect(notch.minX == panel.maxX)
        #expect(!notch.contains(CGPoint(x: anchor.x + 15, y: anchor.y)))
    }

    @Test func largeImagesShrinkToFitAndStayOnScreen() throws {
        let anchor = CGPoint(x: 400, y: 60)
        let panel = try #require(PreviewGeometry.panelFrame(anchor: anchor, naturalSize: CGSize(width: 4000, height: 3000), visible: visible))
        #expect(panel.maxX <= visible.maxX)
        #expect(panel.minY >= visible.minY)
        #expect(panel.maxY <= visible.maxY)
        #expect(abs((panel.width - 8) / (panel.height - 8) - 4.0 / 3.0) < 0.01)
    }
}

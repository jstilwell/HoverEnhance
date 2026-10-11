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

/// Whether a preview would be worth it next to what the page already shows.
struct EnlargementTests {
    private let room = CGSize(width: 900, height: 700)

    @Test func thumbnailsAreEnlarged() {
        #expect(PreviewGeometry.couldEnlarge(shown: CGSize(width: 200, height: 150), room: room, by: 1.2))
        #expect(PreviewGeometry.enlarges(CGSize(width: 2000, height: 1500), shown: CGSize(width: 200, height: 150), room: room, by: 1.2))
    }

    @Test func imagesShownAboutAsLargeAsThePreviewAreLeftAlone() {
        // 640×600 on the page; a preview of the same shape can't pass 700 tall.
        #expect(!PreviewGeometry.couldEnlarge(shown: CGSize(width: 640, height: 600), room: room, by: 1.2))
    }

    @Test func largeFilesCountAtTheSizeThePreviewShows() {
        // Shown at 600×450; the 4000×3000 file would show at 900×675, only 1.5× as large.
        let shown = CGSize(width: 600, height: 450)
        #expect(PreviewGeometry.enlarges(CGSize(width: 4000, height: 3000), shown: shown, room: room, by: 1.2))
        #expect(!PreviewGeometry.enlarges(CGSize(width: 4000, height: 3000), shown: shown, room: room, by: 1.6))
        // Never enlarged past its own pixels.
        #expect(!PreviewGeometry.enlarges(CGSize(width: 640, height: 480), shown: shown, room: room, by: 1.2))
    }

    @Test func aCroppedThumbnailOfATallerImageIsEnlarged() {
        // A square crop of a portrait: the preview is much taller, if not wider.
        #expect(PreviewGeometry.enlarges(CGSize(width: 1080, height: 1920), shown: CGSize(width: 300, height: 300), room: room, by: 1.2))
    }
}

struct RockerGeometryTests {
    private let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func sitsAboveTheNotchAgainstThePreview() {
        let anchor = CGPoint(x: 500, y: 500)
        let rocker = PreviewGeometry.rockerFrame(anchor: anchor, placeRight: true, visible: visible)
        let notch = PreviewGeometry.notchFrame(anchor: anchor, placeRight: true)
        #expect(rocker.maxY == notch.minY - PreviewGeometry.rockerSpacing)
        // Against the preview, which starts `gap` past the cursor; over the cursor's column.
        #expect(rocker.maxX == anchor.x + PreviewGeometry.gap - PreviewGeometry.rockerSpacing)
        #expect(rocker.minX < anchor.x + 1)
    }

    @Test func mirrorsWhenThePreviewIsOnTheLeft() {
        let anchor = CGPoint(x: 1500, y: 500)
        let rocker = PreviewGeometry.rockerFrame(anchor: anchor, placeRight: false, visible: visible)
        #expect(rocker.minX == anchor.x - PreviewGeometry.gap + PreviewGeometry.rockerSpacing)
        #expect(rocker.maxX > anchor.x - 1)
    }

    @Test func goesBelowTheNotchNearTheTopOfTheScreen() {
        let anchor = CGPoint(x: 500, y: 40)
        let rocker = PreviewGeometry.rockerFrame(anchor: anchor, placeRight: true, visible: visible)
        let notch = PreviewGeometry.notchFrame(anchor: anchor, placeRight: true)
        #expect(rocker.minY == notch.maxY + PreviewGeometry.rockerSpacing)
    }

    @Test func theCursorCanCrossFromTheNotchToTheRocker() {
        let anchor = CGPoint(x: 500, y: 500)
        let notch = PreviewGeometry.notchFrame(anchor: anchor, placeRight: true)
        let rocker = PreviewGeometry.rockerFrame(anchor: anchor, placeRight: true, visible: visible)
        let reach = PreviewGeometry.rockerReach(rocker: rocker, notch: notch)
        // Every point straight up from the notch to the rocker, in the rocker's column.
        for y in stride(from: notch.minY, through: rocker.minY, by: -1) {
            #expect(reach.contains(CGPoint(x: rocker.midX, y: y)) || notch.contains(CGPoint(x: rocker.midX, y: y)))
        }
    }
}

struct FileMediaLayoutTests {
    private let details = CGSize(width: 340, height: 400)
    private let room = CGSize(width: 900, height: 1000)

    @Test func wideMediaPutsTheDetailsBelow() {
        let (layout, size) = FileMediaLayout.choose(media: CGSize(width: 1600, height: 900), details: details, room: room)
        #expect(layout == .below)
        #expect(size == CGSize(width: 900, height: 506))
    }

    @Test func tallMediaPutsTheDetailsBeside() {
        let (layout, size) = FileMediaLayout.choose(media: CGSize(width: 900, height: 1600), details: details, room: room)
        #expect(layout == .beside)
        #expect(size.width <= room.width - details.width && size.height <= room.height)
    }

    @Test func smallMediaIsntEnlarged() {
        let (_, size) = FileMediaLayout.choose(media: CGSize(width: 200, height: 150), details: details, room: room)
        #expect(size == CGSize(width: 200, height: 150))
    }

    @Test func detailsTallerThanTheRoomLeaveNoRoomForMedia() {
        // Neither way fits; the caller shows the plain card instead.
        let (_, size) = FileMediaLayout.choose(media: CGSize(width: 300, height: 300), details: CGSize(width: 340, height: 1200),
                                               room: room)
        #expect(size == .zero)
    }
}

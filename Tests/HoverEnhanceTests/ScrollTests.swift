import Foundation
import Testing
@testable import HoverEnhance

struct ScrollInputTests {
    private func input(dx: CGFloat = 0, dy: CGFloat, inverted: Bool) -> ScrollInput {
        ScrollInput(dx: dx, dy: dy, isPrecise: true, isMomentum: false, isInverted: inverted, location: .zero)
    }

    @Test func fingersUpMeansUpWhicheverWayScrollingIsSet() {
        // Natural scrolling: fingers up move content up, which AppKit reports as a negative delta.
        #expect(input(dy: -10, inverted: true).up > 0)
        // Classic scrolling: rolling the wheel away reports a positive delta.
        #expect(input(dy: 10, inverted: false).up > 0)
        #expect(input(dy: 10, inverted: true).up < 0)
    }

    @Test func forwardFollowsTheContentLikeScrollingDownAPage() {
        #expect(input(dy: -10, inverted: true).forward > 0)
        #expect(input(dy: -10, inverted: false).forward > 0)
        #expect(input(dx: -12, dy: 3, inverted: true).forward > 0)
        #expect(input(dy: 10, inverted: true).forward < 0)
    }
}

struct StepAccumulatorTests {
    @Test func wheelNotchesAreOneStepEach() {
        var steps = StepAccumulator()
        #expect(steps.steps(3, precise: false) == 1)
        #expect(steps.steps(-0.5, precise: false) == -1)
        #expect(steps.steps(0, precise: false) == 0)
    }

    @Test func trackpadTravelAddsUp() {
        var steps = StepAccumulator(distance: 40)
        #expect(steps.steps(25, precise: true) == 0)
        #expect(steps.steps(25, precise: true) == 1)
        #expect(steps.steps(85, precise: true) == 2)
        #expect(steps.steps(-30, precise: true) == 0)
        steps.reset()
        #expect(steps.steps(-40, precise: true) == -1)
    }
}

struct ZoomTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func notZoomedFillsTheFrame() {
        #expect(PreviewGeometry.zoomedImageFrame(in: bounds, zoom: 1, focus: CGPoint(x: 0.2, y: 0.9)) == bounds)
    }

    @Test func theFocusPointStaysPut() {
        let focus = CGPoint(x: 0.25, y: 0.75)
        let frame = PreviewGeometry.zoomedImageFrame(in: bounds, zoom: 3, focus: focus)
        #expect(frame.size == CGSize(width: 1200, height: 900))
        // The image point at the focus lands where it was: a quarter across, a quarter up from the bottom.
        #expect(frame.minX + frame.width * focus.x == bounds.width * focus.x)
        #expect(frame.minY + frame.height * (1 - focus.y) == bounds.height * (1 - focus.y))
    }

    @Test func edgesNeverPullInsideTheFrame() {
        for focus in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)] {
            let frame = PreviewGeometry.zoomedImageFrame(in: bounds, zoom: 2, focus: focus)
            #expect(frame.contains(bounds))
        }
    }
}

@MainActor
struct ScrollSettingsTests {
    @Test func defaultsZoomImagesAndScrubVideos() {
        let name = "HoverEnhanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.imageScroll == .zoom)
        #expect(settings.videoScroll == .scrub)
        settings.videoScroll = .volume
        #expect(AppSettings(defaults: defaults).videoScroll == .volume)
    }
}

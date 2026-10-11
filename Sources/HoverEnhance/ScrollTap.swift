import AppKit

/// One scroll-wheel event, reduced to what the preview needs.
struct ScrollInput: Sendable {
    /// Content-direction deltas, as in `NSEvent.scrollingDeltaX/Y`: points from trackpads and Magic
    /// Mice, lines from wheels.
    var dx: CGFloat
    var dy: CGFloat
    var isPrecise: Bool
    /// The glide after a trackpad flick.
    var isMomentum: Bool
    /// "Natural" scrolling, where content follows the fingers.
    var isInverted: Bool
    /// The cursor, in global top-left-origin coordinates.
    var location: CGPoint

    /// Positive when scrolling down or right through content: on to the next item, or later in a video.
    var forward: CGFloat { -(abs(dy) >= abs(dx) ? dy : dx) }

    /// Positive when the fingers or wheel move up or away, whichever way scrolling is set: louder, bigger.
    var up: CGFloat { isInverted ? -dy : dy }

    /// How far to move a video, for `step` seconds a step: a wheel notch, or a step's worth of
    /// trackpad travel, as for albums.
    func scrubSeconds(perStep step: Double) -> Double {
        guard isPrecise else { return forward > 0 ? step : forward < 0 ? -step : 0 }
        return Double(forward / StepAccumulator.stepDistance) * step
    }
}

/// Turns scrolling into whole steps: a wheel notch is one step; trackpad travel adds up to one per
/// `distance` points.
struct StepAccumulator {
    /// Trackpad travel that makes a step, about what smooth-scrolling tools turn a wheel notch into.
    static let stepDistance: CGFloat = 40
    var distance = stepDistance
    private var total: CGFloat = 0

    mutating func steps(_ amount: CGFloat, precise: Bool) -> Int {
        guard precise else { return amount > 0 ? 1 : amount < 0 ? -1 : 0 }
        total += amount
        let steps = Int(total / distance)
        total -= CGFloat(steps) * distance
        return steps
    }

    mutating func reset() {
        total = 0
    }
}

/// While enabled, offers every scroll-wheel event to `handler`, which can act on it and swallow it so
/// the page underneath doesn't scroll. Swallowing events takes an active event tap, which
/// Accessibility access allows.
@MainActor
final class ScrollTap {
    /// Return true to swallow the event.
    var handler: ((ScrollInput) -> Bool)?
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { install() }
            if let port { CGEvent.tapEnable(tap: port, enable: isEnabled) }
        }
    }

    private var port: CFMachPort?

    private func install() {
        guard port == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<ScrollTap>.fromOpaque(userInfo).takeUnretainedValue()
            // The tap's run loop source is on the main run loop.
            let swallow = MainActor.assumeIsolated { tap.shouldSwallow(type, event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        self.port = port
    }

    private func shouldSwallow(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isEnabled, let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        guard isEnabled, type == .scrollWheel, let handler, let scroll = NSEvent(cgEvent: event) else { return false }
        return handler(ScrollInput(
            dx: scroll.scrollingDeltaX, dy: scroll.scrollingDeltaY,
            isPrecise: scroll.hasPreciseScrollingDeltas, isMomentum: scroll.momentumPhase != [],
            isInverted: scroll.isDirectionInvertedFromDevice, location: event.location
        ))
    }
}

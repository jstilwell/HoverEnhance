import AppKit

/// While enabled, swallows scroll-wheel events and turns them into next/previous steps, so paging
/// through an album doesn't also scroll the page underneath. Swallowing events takes an active
/// event tap, which Accessibility access allows.
@MainActor
final class ScrollTap {
    /// +1 for next, -1 for previous.
    var onStep: ((Int) -> Void)?
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { install() }
            if let port { CGEvent.tapEnable(tap: port, enable: isEnabled) }
            accumulated = 0
        }
    }

    private var port: CFMachPort?
    private var accumulated: CGFloat = 0
    /// Trackpad travel, in points, per step.
    private let stepDistance: CGFloat = 40

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
        guard isEnabled, type == .scrollWheel else { return false }

        if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
            // Mouse wheel: a notch is a step.
            let vertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let delta = vertical != 0 ? vertical : event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            if delta != 0 { onStep?(delta < 0 ? 1 : -1) }
        } else if event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 {
            // Trackpad: step per `stepDistance` of finger travel. Momentum is ignored so a flick
            // doesn't race through the album.
            let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            accumulated += abs(dy) >= abs(dx) ? dy : dx
            while abs(accumulated) >= stepDistance {
                onStep?(accumulated < 0 ? 1 : -1)
                accumulated += accumulated < 0 ? stepDistance : -stepDistance
            }
        }
        return true
    }
}

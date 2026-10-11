import AppKit

/// Watches the mouse and inspects whatever it comes to rest on.
@MainActor
final class HoverMonitor {
    /// How long the cursor must stay still before we inspect. Keeps AX traffic to one query per stop.
    var dwell: TimeInterval { AppSettings.shared.hoverDelay / 1000 }
    var isPaused = false {
        didSet { if isPaused { dwellTimer?.invalidate() } }
    }
    /// Each inspection, and whether it's a second look at the same spot (see `lookAgain`).
    var onResult: ((Result<HoverInfo, InspectionError>, _ again: Bool) -> Void)?
    /// Every mouse move, with the cursor in global top-left-origin coordinates.
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Content moved under the cursor.
    var onScroll: (() -> Void)?
    var onClick: (() -> Void)?
    /// A modifier key went down or up (for the activation key setting).
    var onModifiersChanged: ((NSEvent.ModifierFlags) -> Void)?
    /// Any other key went down. Only that a key was pressed is passed on, never which.
    var onKeyDown: (() -> Void)?

    private let inspector = HoverInspector()
    private var eventMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var dwellTimer: Timer?
    /// Bumped on every mouse move so results that arrive after the cursor has moved on are dropped.
    private var generation = 0

    func start() {
        // Global monitors don't see events while our own app is active, so add a local one too.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown, .flagsChanged, .keyDown]
        eventMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
                self?.handle(event)
            },
            NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.handle(event)
                return event
            },
        ].compactMap { $0 }

        // Switch on Chromium/Electron trees as apps come forward, so the first hover finds content.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [inspector] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                inspector.prepare(pid: app.processIdentifier)
            }
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            inspector.prepare(pid: frontmost.processIdentifier)
        }
    }

    /// Makes the event monitors again after Accessibility access comes back: monitors that outlived
    /// the loss aren't sure to hear key events again.
    func restart() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        start()
    }

    private func handle(_ event: NSEvent) {
        // Clicks and scrolls in our own windows (an interactive preview) are for that window.
        if event.window != nil, event.type != .mouseMoved { return }
        switch event.type {
        case .mouseMoved:
            if let point = CGEvent(source: nil)?.location { onMouseMoved?(point) }
            restartDwell()
        case .scrollWheel:
            // Scrolling changes what's under the cursor, so it counts as movement for the dwell.
            onScroll?()
            restartDwell()
        case .flagsChanged:
            onModifiersChanged?(event.modifierFlags)
        case .keyDown:
            stopLookingAgain()
            onKeyDown?()
        default:
            stopLookingAgain()
            onClick?()
        }
    }

    /// A click or key press may change the page under a still cursor (a site's own viewer opening, say)
    /// on purpose: no second looks then. Results already on their way are dropped too.
    private func stopLookingAgain() {
        generation += 1
    }

    /// Inspects what's under the cursor now, without waiting for it to rest.
    func inspectNow() {
        generation += 1
        guard !isPaused else { return }
        mouseSettled()
    }

    private func restartDwell() {
        generation += 1
        guard !isPaused else { return }
        if let dwellTimer, dwellTimer.isValid {
            dwellTimer.fireDate = Date(timeIntervalSinceNow: dwell)
        } else {
            dwellTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseSettled() }
            }
        }
    }

    private func mouseSettled() {
        // CGEvent reports the cursor in the same top-left-origin space the AX API uses.
        guard let point = CGEvent(source: nil)?.location else { return }
        // Accessibility questions about this app's own windows are answered in this process, on the
        // inspector's queue: AppKit and SwiftUI would run off the main thread, throw, and leave
        // SwiftUI locked, freezing the app. So they're never asked.
        if OwnWindows.areInFront(at: point) {
            onResult?(.failure(.ownWindow), false)
            return
        }
        let requested = generation
        Task {
            let result = await inspector.inspect(at: point)
            guard requested == generation, !isPaused else { return }
            onResult?(result, false)
            if case .success(let info) = result, info.pageURL != nil {
                await lookAgain(at: point, generation: requested)
            }
        }
    }

    /// A page can still be building what's under a cursor that just stopped: Chromium fills in its
    /// accessibility tree after scrolling and loading, so a first look can come up short. While the
    /// cursor stays put, look a few more times over the next two seconds, until a preview is up.
    private func lookAgain(at point: CGPoint, generation requested: Int) async {
        for delay in [0.2, 0.3, 0.5, 1.0] {
            try? await Task.sleep(for: .seconds(delay))
            guard requested == generation, !isPaused, !OwnWindows.areInFront(at: point) else { return }
            let result = await inspector.inspect(at: point)
            guard requested == generation, !isPaused else { return }
            onResult?(result, true)
        }
    }
}

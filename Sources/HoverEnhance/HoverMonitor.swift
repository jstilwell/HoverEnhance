import AppKit

/// Watches the mouse and inspects whatever it comes to rest on.
@MainActor
final class HoverMonitor {
    /// How long the cursor must stay still before we inspect. Keeps AX traffic to one query per stop.
    var dwell: TimeInterval = 0.15
    var isPaused = false {
        didSet { if isPaused { dwellTimer?.invalidate() } }
    }
    var onResult: ((Result<HoverInfo, InspectionError>) -> Void)?
    /// Every mouse move, with the cursor in global top-left-origin coordinates.
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Content moved under the cursor.
    var onScroll: (() -> Void)?
    var onClick: (() -> Void)?

    private let inspector = HoverInspector()
    private var eventMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var dwellTimer: Timer?
    /// Bumped on every mouse move so results that arrive after the cursor has moved on are dropped.
    private var generation = 0

    func start() {
        // Global monitors don't see events while our own app is active, so add a local one too.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown]
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

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            if let point = CGEvent(source: nil)?.location { onMouseMoved?(point) }
            restartDwell()
        case .scrollWheel:
            // Scrolling changes what's under the cursor, so it counts as movement for the dwell.
            onScroll?()
            restartDwell()
        default:
            onClick?()
        }
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
        let requested = generation
        Task {
            let result = await inspector.inspect(at: point)
            guard requested == generation, !isPaused else { return }
            onResult?(result)
        }
    }
}

import AppKit
import os

/// Watches the mouse and inspects whatever it comes to rest on.
@MainActor
final class HoverMonitor {
    /// How long the cursor must stay still before we inspect. Keeps AX traffic to one query per stop.
    var dwell: TimeInterval { AppSettings.shared.hoverDelay / 1000 }
    /// Nothing is watched while paused: no event monitors, no inspections.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            if isPaused {
                dwellTimer?.invalidate()
                removeEventMonitors()
            } else if isStarted {
                addEventMonitors()
            }
        }
    }
    /// What the settings ask of the inspector right now.
    var policy: () -> InspectionPolicy = { InspectionPolicy() }
    /// Whether a rest is worth a look at all, as it isn't while previews need a key that isn't held.
    var shouldInspect: () -> Bool = { true }
    /// Each inspection, and whether it's a second look at the same spot (see `lookAgain`).
    var onResult: ((Result<HoverInfo, InspectionError>, _ again: Bool) -> Void)?
    /// Every mouse move, with the cursor in global top-left-origin coordinates.
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Content moved under the cursor.
    var onScroll: (() -> Void)?
    /// A click, with where it was in global top-left-origin coordinates.
    var onClick: ((CGPoint?) -> Void)?
    /// A modifier key went down or up (for the activation key setting).
    var onModifiersChanged: ((NSEvent.ModifierFlags) -> Void)?
    /// Any other key went down. Only whether it was Esc is passed on, never which key it was.
    var onKeyDown: ((_ isEscape: Bool) -> Void)?

    private let inspector = HoverInspector()
    private var isStarted = false
    private var eventMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var dwellTimer: Timer?
    /// Bumped on every mouse move so results that arrive after the cursor has moved on are dropped.
    private var generation = 0 {
        didSet {
            let current = generation
            latestGeneration.withLock { $0 = current }
        }
    }
    /// `generation`, for the inspector's queue to drop looks that are no longer wanted.
    private let latestGeneration = OSAllocatedUnfairLock(initialState: 0)
    /// Chromium's tree lags behind a scroll, so a first look just after one can land on stale text.
    private var lastScroll = Date.distantPast

    func start() {
        isStarted = true
        if !isPaused { addEventMonitors() }

        // Switch on Chromium/Electron trees as apps come forward, so the first hover finds content.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                MainActor.assumeIsolated { self?.prepare(app) }
            }
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication { prepare(frontmost) }
    }

    /// Makes the event monitors again after Accessibility access comes back: monitors that outlived
    /// the loss aren't sure to hear key events again.
    func restart() {
        removeEventMonitors()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        start()
    }

    /// The settings changed: switches web trees back off in apps that can't show previews now, or in all
    /// of them while paused, and on in the app in front if it can.
    func settingsChanged() {
        let voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        inspector.switchOff(unlessKeptBy: isPaused ? nil : policy(), voiceOverIsRunning: voiceOver)
        if let frontmost = NSWorkspace.shared.frontmostApplication { prepare(frontmost) }
    }

    /// Leaves apps as they were found, as HoverEnhance quits.
    func stop() {
        removeEventMonitors()
        inspector.switchOff(unlessKeptBy: nil, voiceOverIsRunning: NSWorkspace.shared.isVoiceOverEnabled, wait: true)
    }

    private func prepare(_ app: NSRunningApplication) {
        guard !isPaused else { return }
        inspector.prepare(pid: app.processIdentifier, policy: policy())
    }

    private func addEventMonitors() {
        guard eventMonitors.isEmpty else { return }
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
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
    }

    private func handle(_ event: NSEvent) {
        // Clicks and scrolls in our own windows (an interactive preview) are for that window. Modifier
        // keys still count, so the activation key's state stays right.
        if event.window != nil, event.type != .mouseMoved, event.type != .flagsChanged { return }
        switch event.type {
        case .mouseMoved:
            if let point = CGEvent(source: nil)?.location { onMouseMoved?(point) }
            restartDwell()
        case .scrollWheel:
            // Scrolling changes what's under the cursor, so it counts as movement for the dwell.
            lastScroll = Date()
            onScroll?()
            restartDwell()
        case .flagsChanged:
            onModifiersChanged?(event.modifierFlags)
        case .keyDown:
            stopLookingAgain()
            onKeyDown?(event.keyCode == 53)
        default:
            stopLookingAgain()
            onClick?(event.cgEvent?.location ?? CGEvent(source: nil)?.location)
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
        guard shouldInspect() else { return }
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
        let policy = policy()
        let isWanted: @Sendable () -> Bool = { [latestGeneration] in latestGeneration.withLock { $0 } == requested }
        Task {
            let result = await inspector.inspect(at: point, policy: policy, isWanted: isWanted)
            guard requested == generation, !isPaused else { return }
            onResult?(result, false)
            // Plain text needs no second look, unless the page just scrolled and the tree may be behind.
            if case .success(let info) = result, info.pageURL != nil, !info.isPlainText || Date().timeIntervalSince(lastScroll) < 2 {
                await lookAgain(at: point, generation: requested, policy: policy, isWanted: isWanted)
            }
        }
    }

    /// A page can still be building what's under a cursor that just stopped: Chromium fills in its
    /// accessibility tree after scrolling and loading, so a first look can come up short. While the
    /// cursor stays put, look a few more times over the next two seconds, until a preview is up.
    private func lookAgain(at point: CGPoint, generation requested: Int, policy: InspectionPolicy,
                           isWanted: @escaping @Sendable () -> Bool) async {
        for delay in [0.2, 0.3, 0.5, 1.0] {
            try? await Task.sleep(for: .seconds(delay))
            guard requested == generation, !isPaused, !OwnWindows.areInFront(at: point) else { return }
            let result = await inspector.inspect(at: point, policy: policy, isWanted: isWanted)
            guard requested == generation, !isPaused else { return }
            onResult?(result, true)
        }
    }
}

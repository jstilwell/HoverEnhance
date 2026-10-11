import AppKit
import ApplicationServices
import Observation

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}

/// Follows whether this app has Accessibility access. macOS posts no notification of its own for
/// this app, so it's checked every second while access is off, and whenever the system says the list
/// of trusted apps changed.
@MainActor @Observable
final class AccessibilityWatcher {
    private(set) var isGranted: Bool
    /// Called when access is turned on or off.
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    @ObservationIgnored private let isTrusted: @MainActor () -> Bool
    @ObservationIgnored private let interval: TimeInterval
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var listObserver: NSObjectProtocol?

    init(interval: TimeInterval = 1, isTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() }) {
        self.interval = interval
        self.isTrusted = isTrusted
        isGranted = isTrusted()
    }

    func start() {
        // Posted, undocumented, when any app is added to or removed from the list. Trust can take a
        // moment to settle afterward.
        listObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self?.check()
            }
        }
        updateTimer()
    }

    /// Reads access now, as after an accessibility call failed for want of it.
    func check() {
        let granted = isTrusted()
        guard granted != isGranted else { return }
        isGranted = granted
        updateTimer()
        onChange?(granted)
    }

    private func updateTimer() {
        timer?.invalidate()
        timer = nil
        guard !isGranted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }
}

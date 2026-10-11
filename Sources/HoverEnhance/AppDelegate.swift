import AppKit
import OSLog

let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HoverEnhance", category: "hover")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = HoverMonitor()
    private let preview = PreviewController()
    private let hud = HUD()
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem?
    private var lastInfo: HoverInfo?

    private var previewsEnabled: Bool {
        get { defaults.bool(forKey: "previewsEnabled") }
        set { defaults.set(newValue, forKey: "previewsEnabled") }
    }
    private var showsInspector: Bool {
        get { defaults.bool(forKey: "showsInspector") }
        set { defaults.set(newValue, forKey: "showsInspector") }
    }

    private var permissionItem: NSMenuItem!
    private var grantItem: NSMenuItem!
    private var previewsItem: NSMenuItem!
    private var inspectorItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var copyItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["previewsEnabled": true, "showsInspector": false])
        preview.isEnabled = previewsEnabled

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "HoverEnhance")
        item.menu = makeMenu()
        statusItem = item

        monitor.onResult = { [weak self] result in self?.handle(result) }
        monitor.onMouseMoved = { [weak self] point in self?.preview.mouseMoved(to: point) }
        monitor.onScroll = { [weak self] in self?.preview.scrolled() }
        monitor.onClick = { [weak self] in self?.preview.dismiss() }
        monitor.start()

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
    }

    private func handle(_ result: Result<HoverInfo, InspectionError>) {
        switch result {
        case .success(let info):
            preview.hovered(info)
            guard info != lastInfo else { return }
            lastInfo = info
            print(info.summary + "\n")
            // Info-level messages stay in memory rather than the persisted log; `make log` streams them.
            log.info("\(info.summary, privacy: .public)")
            if showsInspector { hud.show(info.summary) }
        case .failure(.ownWindow):
            break
        case .failure(let error):
            preview.reset(because: "inspection failed: \(error)")
            lastInfo = nil
            if showsInspector { hud.show(error.message) }
        }
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        grantItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
        previewsItem = NSMenuItem(title: "Image Previews", action: #selector(togglePreviews), keyEquivalent: "i")
        inspectorItem = NSMenuItem(title: "Show Inspector", action: #selector(toggleInspector), keyEquivalent: "h")
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        copyItem = NSMenuItem(title: "Copy Last Result", action: #selector(copyLastResult), keyEquivalent: "c")
        for item in [grantItem, previewsItem, inspectorItem, pauseItem, copyItem] {
            item?.target = self
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.items = [
            permissionItem, grantItem, .separator(),
            previewsItem, inspectorItem, pauseItem, .separator(),
            copyItem, .separator(),
            NSMenuItem(title: "Quit HoverEnhance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let granted = AccessibilityPermission.isGranted
        permissionItem.title = granted ? "Accessibility access: on" : "Accessibility access: off"
        permissionItem.isEnabled = false
        grantItem.isHidden = granted
        previewsItem.state = previewsEnabled ? .on : .off
        inspectorItem.state = showsInspector ? .on : .off
        pauseItem.state = monitor.isPaused ? .on : .off
        copyItem.isEnabled = lastInfo != nil
    }

    @objc private func grantAccess() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
    }

    @objc private func togglePreviews() {
        previewsEnabled.toggle()
        preview.isEnabled = previewsEnabled
    }

    @objc private func toggleInspector() {
        showsInspector.toggle()
        if showsInspector, let lastInfo {
            hud.show(lastInfo.summary)
        } else {
            hud.hide()
        }
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        if monitor.isPaused {
            preview.reset(because: "paused")
            hud.hide()
        }
    }

    @objc private func copyLastResult() {
        guard let lastInfo else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastInfo.summary, forType: .string)
    }
}

import AppKit
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HoverEnhance", category: "hover")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = HoverMonitor()
    private let hud = HUD()
    private var statusItem: NSStatusItem?
    private var lastInfo: HoverInfo?
    private var showsHUD = true

    private var permissionItem: NSMenuItem!
    private var grantItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var hudItem: NSMenuItem!
    private var copyItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "HoverEnhance")
        item.menu = makeMenu()
        statusItem = item

        monitor.onResult = { [weak self] result in self?.handle(result) }
        monitor.start()

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
    }

    private func handle(_ result: Result<HoverInfo, InspectionError>) {
        switch result {
        case .success(let info):
            guard info != lastInfo else { return }
            lastInfo = info
            print(info.summary + "\n")
            // Info-level messages stay in memory rather than the persisted log; `make log` streams them.
            log.info("\(info.summary, privacy: .public)")
            if showsHUD { hud.show(info.summary) }
        case .failure(.ownWindow):
            break
        case .failure(let error):
            lastInfo = nil
            if showsHUD { hud.show(error.message) }
        }
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        grantItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        hudItem = NSMenuItem(title: "Show HUD", action: #selector(toggleHUD), keyEquivalent: "h")
        copyItem = NSMenuItem(title: "Copy Last Result", action: #selector(copyLastResult), keyEquivalent: "c")
        for item in [grantItem, pauseItem, hudItem, copyItem] {
            item?.target = self
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.items = [
            permissionItem, grantItem, .separator(),
            pauseItem, hudItem, copyItem, .separator(),
            NSMenuItem(title: "Quit HoverEnhance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let granted = AccessibilityPermission.isGranted
        permissionItem.title = granted ? "Accessibility access: on" : "Accessibility access: off"
        permissionItem.isEnabled = false
        grantItem.isHidden = granted
        pauseItem.state = monitor.isPaused ? .on : .off
        hudItem.state = showsHUD ? .on : .off
        copyItem.isEnabled = lastInfo != nil
    }

    @objc private func grantAccess() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        if monitor.isPaused { hud.hide() }
    }

    @objc private func toggleHUD() {
        showsHUD.toggle()
        if showsHUD, let lastInfo {
            hud.show(lastInfo.summary)
        } else {
            hud.hide()
        }
    }

    @objc private func copyLastResult() {
        guard let lastInfo else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastInfo.summary, forType: .string)
    }
}

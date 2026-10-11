import AppKit
import OSLog

let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HoverEnhance", category: "hover")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private let monitor = HoverMonitor()
    private let preview = PreviewController()
    private let hud = HUD()
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var lastInfo: HoverInfo?

    private var permissionItem: NSMenuItem!
    private var grantItem: NSMenuItem!
    private var previewsItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var copyItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "HoverEnhance")
        item.menu = makeMenu()
        statusItem = item
        installMainMenu()

        monitor.onResult = { [weak self] result in self?.handle(result) }
        monitor.onMouseMoved = { [weak self] point in self?.preview.mouseMoved(to: point) }
        monitor.onScroll = { [weak self] in self?.preview.scrolled() }
        monitor.onClick = { [weak self] in self?.preview.dismiss() }
        monitor.onModifiersChanged = { [weak self] flags in self?.modifiersChanged(flags) }
        monitor.start()

        NotificationCenter.default.addObserver(forName: .showSettingsTab, object: nil, queue: .main) { [weak self] note in
            let tab = note.object as? String
            MainActor.assumeIsolated {
                self?.preview.reset(because: "opening settings")
                self?.openSettings(tab: tab)
            }
        }
        whenChanged({ AppSettings.shared.previewsEnabled }) { [weak self] enabled in
            if !enabled { self?.preview.reset(because: "previews turned off") }
        }
        whenChanged({ AppSettings.shared.showsInspector }) { [weak self] shows in
            guard let self else { return }
            if shows, let lastInfo { hud.show(lastInfo.summary) } else { hud.hide() }
        }

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
    }

    /// Opening the app again (from Finder, Spotlight, or `open`) while it runs shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
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
            if settings.showsInspector { hud.show(info.summary) }
        case .failure(.ownWindow):
            break
        case .failure(let error):
            preview.reset(because: "inspection failed: \(error)")
            lastInfo = nil
            if settings.showsInspector { hud.show(error.message) }
        }
    }

    /// With an activation key set, pressing or releasing it shows or hides the preview without
    /// waiting for the mouse to move.
    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        guard settings.activation != .always else { return }
        if settings.previewsAllowed(holding: flags) {
            monitor.inspectNow()
        } else {
            preview.reset(because: "activation key")
        }
    }

    /// Calls `perform` with the new value whenever `read`'s settings change.
    private func whenChanged<Value: Sendable>(
        _ read: @escaping @MainActor @Sendable () -> Value,
        perform: @escaping @MainActor @Sendable (Value) -> Void
    ) {
        withObservationTracking { _ = read() } onChange: {
            Task { @MainActor in
                perform(read())
                self.whenChanged(read, perform: perform)
            }
        }
    }

    // MARK: - Menus

    private func makeMenu() -> NSMenu {
        permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        grantItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
        previewsItem = NSMenuItem(title: "Enable Previews", action: #selector(togglePreviews), keyEquivalent: "e")
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        copyItem = NSMenuItem(title: "Copy Inspector Result", action: #selector(copyLastResult), keyEquivalent: "c")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        for item in [grantItem, previewsItem, pauseItem, copyItem, settingsItem] {
            item?.target = self
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.items = [
            permissionItem, grantItem, .separator(),
            previewsItem, pauseItem, copyItem, .separator(),
            settingsItem, .separator(),
            NSMenuItem(title: "Quit HoverEnhance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        return menu
    }

    /// Never shown for a menu bar app, but it gives the Settings window ⌘, ⌘W, and ⌘Q.
    private func installMainMenu() {
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.items = [
            settingsItem, .separator(),
            NSMenuItem(title: "Quit HoverEnhance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        let windowMenu = NSMenu(title: "Window")
        windowMenu.items = [NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")]

        let main = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let granted = AccessibilityPermission.isGranted
        permissionItem.title = granted ? "Accessibility access: on" : "Accessibility access: off"
        permissionItem.isEnabled = false
        grantItem.isHidden = granted
        previewsItem.state = settings.previewsEnabled ? .on : .off
        pauseItem.state = monitor.isPaused ? .on : .off
        copyItem.isHidden = !settings.showsInspector
        copyItem.isEnabled = lastInfo != nil
    }

    @objc private func showSettings() {
        openSettings(tab: nil)
    }

    private func openSettings(tab: String?) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(settings: settings) }
        settingsWindow?.show(tab: tab)
    }

    @objc private func grantAccess() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
    }

    @objc private func togglePreviews() {
        settings.previewsEnabled.toggle()
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

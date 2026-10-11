import AppKit
import OSLog

let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HoverEnhance", category: "hover")

extension Logger {
    /// For messages holding URLs, paths, or text from other apps: readable in debug builds, where
    /// `make log` shows them, and redacted in release builds, where the log is no place for what the
    /// user looks at.
    func infoPrivateInRelease(_ message: String) {
        #if DEBUG
        info("\(message, privacy: .public)")
        #else
        info("\(message, privacy: .private)")
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private let monitor = HoverMonitor()
    private let preview = PreviewController()
    private let hud = HUD()
    private let access = AccessibilityWatcher()
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var aboutWindow: AboutWindowController?
    private var welcome: WelcomeWindowController?
    /// Whether the app proper is up: the menu bar item and the hover monitor. It waits for access.
    private var isRunning = false
    private var lastInfo: HoverInfo?

    private var versionItem: NSMenuItem!
    private var grantItem: NSMenuItem!
    private var previewsItem: NSMenuItem!
    private var copyItem: NSMenuItem!
    private var updateItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        // Updates don't depend on Accessibility, so a release that needs fixing can still be replaced.
        Updates.shared.start()
        access.onChange = { [weak self] granted in self?.accessChanged(granted) }
        access.start()
        if access.isGranted { start() } else { showWelcome() }
    }

    /// Everything but the welcome window. Without Accessibility access none of it could work, so it
    /// starts only once access is on.
    private func start() {
        guard !isRunning else { return }
        isRunning = true
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.image()
        item.menu = makeMenu()
        statusItem = item

        monitor.onResult = { [weak self] result, again in self?.handle(result, again: again) }
        monitor.onMouseMoved = { [weak self] point in self?.preview.mouseMoved(to: point) }
        monitor.onScroll = { [weak self] in self?.preview.scrolled() }
        monitor.onClick = { [weak self] in self?.preview.dismiss() }
        monitor.onModifiersChanged = { [weak self] flags in self?.modifiersChanged(flags) }
        monitor.onKeyDown = { [weak self] in self?.preview.keyPressed() }
        monitor.start()

        NotificationCenter.default.addObserver(forName: .showSettingsTab, object: nil, queue: .main) { [weak self] note in
            let tab = note.object as? SettingsTab
            MainActor.assumeIsolated {
                self?.preview.reset(because: "opening settings")
                self?.openSettings(tab: tab)
            }
        }
        whenChanged({ AppSettings.shared.previewsEnabled }) { [weak self] enabled in
            if !enabled { self?.preview.reset(because: "previews turned off") }
            self?.updateActivity()
        }
        whenChanged({ AppSettings.shared.showsInspector }) { [weak self] shows in
            guard let self else { return }
            if shows, let lastInfo { hud.show(lastInfo.summary) } else { hud.hide() }
            updateActivity()
        }
        updateActivity()
        whenChanged({ Updates.shared.waitingVersion }) { [weak self] version in
            self?.statusItem?.button?.image = MenuBarIcon.image(badged: version != nil)
        }
        NotificationCenter.default.addObserver(forName: .showAccessibilityGuide, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showWelcome() }
        }
    }

    /// Inspects only while something uses what's found, and dims the menu bar icon while previews are off.
    private func updateActivity() {
        monitor.isPaused = !settings.previewsEnabled && !settings.showsInspector
        statusItem?.button?.appearsDisabled = !settings.previewsEnabled
    }

    private func accessChanged(_ granted: Bool) {
        if granted {
            if isRunning { monitor.restart() } else { start() }
        } else {
            preview.reset(because: "accessibility access lost")
            hud.hide()
            showWelcome()
        }
    }

    private func showWelcome() {
        if welcome == nil {
            let controller = WelcomeWindowController(access: access, isReturning: isRunning) { [weak self] in self?.showSettings() }
            controller.onClose = { [weak self] in
                guard let self else { return }
                welcome = nil
                // Closed before access was on: there's nothing to run.
                if !isRunning { NSApp.terminate(nil) }
            }
            welcome = controller
        }
        welcome?.show()
    }

    /// Opening the app again (from Finder, Spotlight, or `open`) shows Settings, or the welcome window
    /// while it waits for access.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isRunning { showSettings() } else { showWelcome() }
        return false
    }

    /// `again` is a second look at the spot the cursor stopped on, which only ever adds a preview.
    private func handle(_ result: Result<HoverInfo, InspectionError>, again: Bool = false) {
        switch result {
        case .success(let info):
            preview.hovered(info, again: again)
            guard info != lastInfo else { return }
            lastInfo = info
            #if DEBUG
            // For `make log`. Release builds leave what's under the cursor (text, URLs, paths) out of
            // the log; the inspector shows it to the user instead.
            log.info("\(info.summary, privacy: .public)")
            #endif
            if settings.showsInspector { hud.show(info.summary) }
        case .failure(.ownWindow):
            break
        case .failure(.notTrusted):
            // Access was turned off while running.
            access.check()
        case .failure where again:
            break
        case .failure(let error):
            preview.reset(because: "inspection failed: \(error)")
            lastInfo = nil
            if settings.showsInspector { hud.show(error.message) }
        }
    }

    /// With an activation key in use, pressing or releasing it shows or hides the preview without
    /// waiting for the mouse to move.
    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        guard settings.usesActivationKey else { return }
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
        // Greyed out at the top, as in LockAudio. Accessibility access goes without saying: without it
        // the welcome window shows instead of this menu.
        versionItem = NSMenuItem(title: "Version \(AdvancedSettingsView.shortVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        grantItem = menuItem("Grant Accessibility Access…", action: #selector(grantAccess), symbol: "hand.raised")
        previewsItem = menuItem("Show Previews", action: #selector(togglePreviews), key: "e", symbol: "eye")
        copyItem = menuItem("Copy Inspector Result", action: #selector(copyLastResult), key: "c", symbol: "doc.on.doc")
        updateItem = menuItem("Check for Updates…", action: #selector(checkForUpdates), symbol: "arrow.triangle.2.circlepath")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.items = [
            versionItem, grantItem, .separator(),
            previewsItem, copyItem, .separator(),
            menuItem("About HoverEnhance", action: #selector(showAbout), symbol: "info.circle"),
            updateItem,
            menuItem("Settings…", action: #selector(showSettings), key: ",", symbol: "gearshape"),
            .separator(),
            menuItem("Quit HoverEnhance", action: #selector(NSApplication.terminate(_:)), key: "q", symbol: "xmark.circle", target: NSApp),
        ]
        return menu
    }

    /// A menu item with a symbol before its title, as in LockAudio's menu.
    private func menuItem(_ title: String, action: Selector?, key: String = "", symbol: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        // macOS 27 hides menu items' images unless they ask to be shown.
        if #available(macOS 27, *) { item.preferredImageVisibility = .visible }
        return item
    }

    /// Never shown for a menu bar app, but it gives the Settings window ⌘, ⌘W, and ⌘Q.
    private func installMainMenu() {
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "About HoverEnhance", action: #selector(showAbout), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        aboutItem.target = self
        settingsItem.target = self
        appMenu.items = [
            aboutItem, .separator(),
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
        let granted = access.isGranted
        grantItem.isHidden = granted
        previewsItem.state = settings.previewsEnabled ? .on : .off
        copyItem.isHidden = !settings.showsInspector
        copyItem.isEnabled = lastInfo != nil
        let updates = Updates.shared
        updateItem.isHidden = !updates.isAvailable
        updateItem.title = updates.waitingVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
    }

    @objc private func checkForUpdates() {
        Updates.shared.checkForUpdates()
    }

    @objc private func showAbout() {
        if aboutWindow == nil { aboutWindow = AboutWindowController() }
        aboutWindow?.show()
    }

    @objc private func showSettings() {
        openSettings(tab: nil)
    }

    private func openSettings(tab: SettingsTab?) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(settings: settings, access: access) }
        settingsWindow?.show(tab: tab)
    }

    @objc private func grantAccess() {
        showWelcome()
    }

    @objc private func togglePreviews() {
        settings.previewsEnabled.toggle()
    }

    @objc private func copyLastResult() {
        guard let lastInfo else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastInfo.summary, forType: .string)
    }
}

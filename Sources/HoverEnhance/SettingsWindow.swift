import AppKit
import SwiftUI

/// The Settings window: a toolbar of tabs, each a SwiftUI form bound to `AppSettings`.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        func add<Content: View>(_ title: String, _ symbol: String, _ view: Content) {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("General", "gearshape", GeneralSettingsView(settings: settings))
        add("Previews", "photo.on.rectangle", PreviewsSettingsView(settings: settings))
        add("Video", "play.rectangle", VideoSettingsView(settings: settings))
        add("Sites", "globe", SitesSettingsView(settings: settings))
        add("Finder", "folder", FinderSettingsView(settings: settings))
        add("Accounts", "person.crop.circle", AccountsSettingsView(account: YouTubeAccount.shared))
        add("Advanced", "wrench.and.screwdriver", AdvancedSettingsView(settings: settings))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the window with the tab titled `tab` selected, if there is one.
    func show(tab: String?) {
        if let tab, let tabs = contentViewController as? NSTabViewController,
           let index = tabs.tabViewItems.firstIndex(where: { $0.label == tab }) {
            tabs.selectedTabViewItemIndex = index
        }
        show()
    }

    func show() {
        guard let window else { return }
        // A menu bar app isn't frontmost on its own; without this the window opens behind others.
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }
}

/// Housekeeping the Advanced tab offers.
enum Maintenance {
    static var imageCacheBytes: Int { ImageLoader.diskCache.currentDiskUsage }

    static func clearImageCache() {
        ImageLoader.diskCache.removeAllCachedResponses()
    }

    /// Cookies and storage from pages HoverEnhance loads, such as the cookie from Reddit's browser check.
    @MainActor
    static func clearWebsiteData() async {
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        await WebPageLoader.clearWebsiteData()
    }
}

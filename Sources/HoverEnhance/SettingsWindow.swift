import AppKit
import SwiftUI

/// The Settings window's tabs, in order.
enum SettingsTab: String, CaseIterable, Sendable {
    case general, previews, video, sites, finder, accounts, advanced

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .previews: "photo.on.rectangle"
        case .video: "play.rectangle"
        case .sites: "globe"
        case .finder: "folder"
        case .accounts: "person.crop.circle"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}

/// The Settings window: a toolbar of tabs, each a SwiftUI form bound to `AppSettings`.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, access: AccessibilityWatcher) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        func host<Content: View>(_ view: Content) -> NSViewController {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            return host
        }
        for tab in SettingsTab.allCases {
            let host = switch tab {
            case .general: host(GeneralSettingsView(settings: settings))
            case .previews: host(PreviewsSettingsView(settings: settings))
            case .video: host(VideoSettingsView(settings: settings))
            case .sites: host(SitesSettingsView(settings: settings))
            case .finder: host(FinderSettingsView(settings: settings))
            case .accounts: host(AccountsSettingsView(account: YouTubeAccount.shared))
            case .advanced: host(AdvancedSettingsView(settings: settings, access: access, updates: Updates.shared))
            }
            host.title = tab.title
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the window with `tab` selected, if given.
    func show(tab: SettingsTab?) {
        if let tab, let tabs = contentViewController as? NSTabViewController,
           let index = tabs.tabViewItems.firstIndex(where: { $0.identifier as? String == tab.rawValue }) {
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

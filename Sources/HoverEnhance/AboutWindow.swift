import AppKit
import SwiftUI

/// The About window: the app's icon, name, version, where to find it, and its copyright.
@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "About HoverEnhance"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let host = NSHostingController(rootView: AboutView())
        host.sizingOptions = .preferredContentSize
        window.contentViewController = host
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        window?.showFromMenuBar()
    }
}

struct AboutView: View {
    static let website = URL(string: "https://www.hoverenhance.com")!
    static let repository = URL(string: "https://github.com/jstilwell/HoverEnhance")!
    static let email = "jesse@stilwe.com"

    /// The app's Info.plist, for its version and copyright.
    var info: [String: Any] = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("HoverEnhance")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 12)
            if let version = info["CFBundleShortVersionString"] as? String {
                Text("Version \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            VStack(spacing: 4) {
                Link(Self.website.absoluteString, destination: Self.website)
                Link(Self.repository.absoluteString, destination: Self.repository)
                Link(Self.email, destination: URL(string: "mailto:\(Self.email)")!)
            }
            .font(.system(size: 12))
            .padding(.top, 18)
            if let copyright = info["NSHumanReadableCopyright"] as? String {
                Text(copyright)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 24)
            }
        }
        // Room at the top for the window's close button.
        .padding(.top, 40)
        .padding(.bottom, 32)
        .frame(width: 460)
    }
}

import Foundation
import os

/// What kind of app the cursor is over, from what it tells macOS it can open.
///
/// Previews that load from the network belong in browsers: there, loading what a link points at does
/// no more than the page itself could. In an email app the same request can tell the sender that their
/// message was read, and from where.
enum AppKind: String, Sendable, Equatable {
    /// Opens web links and HTML files: Safari, Chrome, Firefox, and the like.
    case browser
    /// Handles `mailto:` links and isn't a browser: Mail, Outlook, Spark, and the like.
    case email
    case other

    /// Reads an app's Info.plist. Some apps that aren't browsers take web links to do something
    /// with them (a video downloader, say), so a browser must also open HTML files.
    init(infoDictionary info: [String: Any]) {
        let schemes = Set((info["CFBundleURLTypes"] as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .map { $0.lowercased() })
        let documentTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        let opensHTML = documentTypes.contains { type in
            (type["LSItemContentTypes"] as? [String] ?? []).contains { $0.lowercased() == "public.html" }
                || (type["CFBundleTypeExtensions"] as? [String] ?? []).contains { ["html", "htm"].contains($0.lowercased()) }
        }
        if !schemes.isDisjoint(with: ["http", "https"]), opensHTML {
            self = .browser
        } else if schemes.contains("mailto") {
            self = .email
        } else {
            self = .other
        }
    }

    private static let known = OSAllocatedUnfairLock<[URL: AppKind]>(initialState: [:])

    /// The kind of the app at `bundleURL`, read once per app.
    static func of(appAt bundleURL: URL) -> AppKind {
        if let kind = known.withLock({ $0[bundleURL] }) { return kind }
        // Read directly rather than through `Bundle`, which would keep every hovered app's bundle cached.
        let info = CFBundleCopyInfoDictionaryInDirectory(bundleURL as CFURL) as? [String: Any] ?? [:]
        let kind = AppKind(infoDictionary: info)
        known.withLock { $0[bundleURL] = kind }
        return kind
    }
}

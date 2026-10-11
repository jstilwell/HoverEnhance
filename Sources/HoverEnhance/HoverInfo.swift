import Foundation

/// A snapshot of the UI element under the cursor, made of plain values so it can cross threads.
struct HoverInfo: Sendable, Equatable {
    var pid: pid_t
    var appName: String?
    var bundleID: String?
    /// Whether the app is a browser, an email app, or something else.
    var appKind = AppKind.other

    var role: String?
    var subrole: String?
    var title: String?
    /// `AXDescription`; for web images this is usually the alt text.
    var label: String?
    var value: String?
    /// The element's own `AXURL`. For web images this is typically the image source.
    var url: URL?
    /// `AXURL` of the nearest enclosing `AXLink`.
    var linkURL: URL?
    /// `AXURL` of the enclosing `AXWebArea`, i.e. the page being viewed.
    var pageURL: URL?
    /// The image under the cursor: the element itself, or one beneath an overlay covering it.
    var imageURL: URL?
    var imageFrame: CGRect?
    /// The cursor is on a link's text, as opposed to its image or video.
    var isOnText = false
    /// A video the page itself shows under the cursor, playing or not.
    var videoFrame: CGRect?
    /// In Finder: the file or folder under the cursor.
    var fileURL: URL?
    /// The file is an icon on the desktop rather than an item in a Finder window.
    var fileIsOnDesktop = false
    /// Finder's Quick Look panel is open, or a name is being edited there.
    var finderIsBusy = false
    /// Frame in global display coordinates (top-left origin).
    var frame: CGRect?
    /// Roles from the element up to its web area or window, innermost first.
    var ancestry: [String] = []

    var summary: String {
        var lines = [[appName ?? "pid \(pid)", bundleID.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")]
        func add(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append(key.padding(toLength: 7, withPad: " ", startingAt: 0) + value)
        }
        add("kind", appKind == .other ? nil : appKind.rawValue)
        add("role", [role, subrole].compactMap { $0 }.joined(separator: " / "))
        add("title", title)
        add("label", label)
        add("value", value)
        add("url", url?.absoluteString)
        add("image", imageURL == url ? nil : imageURL?.absoluteString)
        add("link", linkURL?.absoluteString)
        add("page", pageURL?.absoluteString)
        add("text", isOnText ? "yes" : nil)
        add("video", videoFrame.map { "on the page, \(Int($0.width))×\(Int($0.height))" })
        add("file", fileURL?.path(percentEncoded: false))
        add("finder", finderIsBusy ? "busy (Quick Look or renaming)" : nil)
        add("frame", frame.map { "\(Int($0.minX)),\(Int($0.minY))  \(Int($0.width))×\(Int($0.height))" })
        add("path", Self.collapsingRepeats(ancestry).joined(separator: " › "))
        return lines.joined(separator: "\n")
    }

    /// ["AXGroup", "AXGroup", "AXLink"] → ["AXGroup×2", "AXLink"]; web pages nest groups deeply.
    private static func collapsingRepeats(_ roles: [String]) -> [String] {
        var runs: [(role: String, count: Int)] = []
        for role in roles {
            if runs.last?.role == role {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((role, 1))
            }
        }
        return runs.map { $0.count > 1 ? "\($0.role)×\($0.count)" : $0.role }
    }
}

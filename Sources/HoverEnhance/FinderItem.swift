import ApplicationServices
import Foundation

/// The parts of an accessibility element the Finder item lookup reads, so it can be tested without Finder.
protocol FinderNode {
    var role: String? { get }
    var parent: Self? { get }
    var children: [Self] { get }
    /// The file or folder this element stands for, if it's a Finder item.
    var itemURL: URL? { get }
}

extension AXElement: FinderNode {
    var itemURL: URL? {
        // Items have a file name; path bar segments and the sidebar don't. Desktop stacks have no URL.
        guard attribute("AXFilename") is String, let value = attribute(kAXURLAttribute) else { return nil }
        return FinderItem.filePathURL(value)
    }
}

/// Finds the file or folder the cursor is on in Finder.
///
/// Finder exposes each item as one element with `AXFilename` and a file reference `AXURL`: the name
/// in list and column view, the icon in icon and gallery view, and desktop icons. The rest of a list
/// row, and the label under an icon, reach it through the row or the item's group.
enum FinderItem {
    static let bundleID = "com.apple.finder"

    static func url<Node: FinderNode>(at element: Node) -> URL? {
        var node: Node? = element
        for _ in 0..<4 {
            guard let current = node else { return nil }
            if let url = current.itemURL { return url }
            switch current.role {
            case "AXRow":
                // A list row: the item is in the name cell.
                return itemURLs(under: current).first
            case "AXGroup":
                // An item's group sits in a list (icon, column, and gallery view). The desktop's group,
                // which holds every desktop icon, doesn't.
                guard current.parent?.role == "AXList" else { return nil }
                let urls = itemURLs(under: current)
                return urls.count == 1 ? urls[0] : nil
            case "AXList", "AXOutline", "AXBrowser", "AXScrollArea", "AXWindow", nil:
                return nil
            default:
                node = current.parent
            }
        }
        return nil
    }

    /// Finder's `AXURL` values are file reference URLs (file:///.file/id=…). Swift's `URL` can't hold
    /// one, so it's turned into a path while still a `CFURL`. Nil for other kinds of URL, such as the
    /// Network item's.
    static func filePathURL(_ value: CFTypeRef) -> URL? {
        guard CFGetTypeID(value) == CFURLGetTypeID(),
              let path = CFURLCreateFilePathURL(nil, (value as! CFURL), nil)?.takeRetainedValue() else { return nil }
        return path as URL
    }

    /// Item URLs among the children and grandchildren of `node`.
    private static func itemURLs<Node: FinderNode>(under node: Node) -> [URL] {
        var urls: [URL] = []
        for child in node.children {
            if let url = child.itemURL {
                urls.append(url)
                continue
            }
            urls += child.children.compactMap(\.itemURL)
        }
        return urls
    }
}

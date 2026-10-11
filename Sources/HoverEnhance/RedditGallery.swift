import Foundation

/// Reddit gallery posts. Reddit's JSON API blocks scripted clients, but the gallery's own web page
/// lists every image in a `<gallery-carousel>` element.
enum RedditGallery {
    private static let hosts: Set<String> = ["reddit.com", "www.reddit.com", "old.reddit.com", "new.reddit.com", "np.reddit.com"]

    /// reddit.com/gallery/<id>
    static func id(fromLink url: URL) -> String? {
        guard let host = url.host()?.lowercased(), hosts.contains(host) else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "gallery",
              parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return parts[2]
    }

    static func pageURL(id: String) -> URL {
        URL(string: "https://www.reddit.com/gallery/\(id)")!
    }

    /// One image URL per gallery item, in order. Each item shows up several times in the carousel
    /// (thumbnail, lazy-loaded preview, full size); the full-size i.redd.it URL is preferred.
    static func imageURLs(inPage html: String) -> [URL] {
        guard let start = html.range(of: "<gallery-carousel"),
              let end = html.range(of: "</gallery-carousel>", range: start.upperBound..<html.endIndex) else { return [] }

        var order: [String] = []
        var best: [String: URL] = [:]
        for match in html[start.lowerBound..<end.lowerBound].matches(of: /(?:src|data-lazy-src)="([^"]+)"/) {
            let string = match.1.replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: string), let id = mediaID(of: url) else { continue }
            if best[id] == nil {
                order.append(id)
                best[id] = url
            } else if url.host() == "i.redd.it" {
                best[id] = url
            }
        }
        return order.compactMap { best[$0] }
    }

    /// i.redd.it/<id>.jpg and preview.redd.it/[<slug>-v0-]<id>.jpg → <id>
    private static func mediaID(of url: URL) -> String? {
        guard let host = url.host(), host == "i.redd.it" || host == "preview.redd.it" else { return nil }
        return url.deletingPathExtension().lastPathComponent.components(separatedBy: "-v0-").last
    }
}

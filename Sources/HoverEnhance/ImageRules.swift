import Foundation

/// Decides what to preview for a hover result: full-size image URLs, best first.
enum ImageResolver {
    static func candidates(for info: HoverInfo) -> [URL] {
        var urls: [URL] = []
        // A link's target is usually the full image, so it outranks the thumbnail being shown.
        if let link = info.linkURL {
            urls += ImageRules.candidates(forLink: link)
        }
        if let image = info.imageURL, ImageRules.isFetchable(image) {
            urls += ImageRules.fullSize(of: image) + [image]
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}

/// Knowledge of where sites keep their full-size images.
enum ImageRules {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "heif", "bmp", "tif", "tiff",
    ]

    /// `blob:` and other browser-internal URLs can't be fetched from outside the browser.
    static func isFetchable(_ url: URL) -> Bool {
        ["http", "https", "file", "data"].contains(url.scheme?.lowercased() ?? "")
    }

    static func isDirectImage(_ url: URL) -> Bool {
        isFetchable(url) && imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Images a link leads to: the target itself if it's an image file, or what a known page shows.
    static func candidates(forLink link: URL) -> [URL] {
        if isDirectImage(link) {
            return fullSize(of: link) + [link]
        }
        switch link.host()?.lowercased() {
        case "imgur.com", "www.imgur.com", "m.imgur.com": return imgurPage(link)
        case "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be": return youtubeVideo(link)
        default: return []
        }
    }

    /// Larger versions of an image, best first, not including the image itself.
    static func fullSize(of image: URL) -> [URL] {
        switch image.host()?.lowercased() {
        case "cdn.bsky.app": bluesky(image)
        case "preview.redd.it": reddit(image)
        case "i.imgur.com": imgur(image)
        case "upload.wikimedia.org": wikimedia(image)
        case "i.ytimg.com", "img.youtube.com": youtube(image)
        case "a.ltrbxd.com": letterboxd(image)
        default: []
        }
    }

    // MARK: - Sites

    /// cdn.bsky.app/img/<preset>/plain/<did>/<cid>@jpeg: the thumbnail presets have full-size siblings.
    private static func bluesky(_ url: URL) -> [URL] {
        let presets = ["feed_thumbnail": "feed_fullsize", "avatar_thumbnail": "avatar"]
        let string = url.absoluteString
        for (thumbnail, full) in presets where string.contains("/img/\(thumbnail)/") {
            return urls(string.replacingOccurrences(of: "/img/\(thumbnail)/", with: "/img/\(full)/"))
        }
        return []
    }

    /// preview.redd.it/<name>?width=…&s=… is a resized copy of i.redd.it/<id>. Newer names put a
    /// title slug in front of the id: "<slug>-v0-<id>.jpeg".
    private static func reddit(_ url: URL) -> [URL] {
        guard let id = url.lastPathComponent.components(separatedBy: "-v0-").last, !id.isEmpty else { return [] }
        return urls("https://i.redd.it/\(id)")
    }

    /// i.imgur.com/<id><size>.<ext>: ids are 5 or 7 characters, and a trailing s/b/t/m/l/h picks a
    /// thumbnail size.
    private static func imgur(_ url: URL) -> [URL] {
        let name = url.deletingPathExtension().lastPathComponent
        guard [6, 8].contains(name.count), let size = name.last, "sbtmlh".contains(size) else { return [] }
        return urls("https://i.imgur.com/\(name.dropLast()).\(url.pathExtension)")
    }

    /// imgur.com/<id> is a single-image page.
    private static func imgurPage(_ url: URL) -> [URL] {
        let parts = url.pathComponents.dropFirst()
        guard parts.count == 1, let id = parts.first, [5, 7].contains(id.count),
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return [] }
        return urls("https://i.imgur.com/\(id).jpg")
    }

    /// upload.wikimedia.org/<project>/<wiki>/thumb/<a>/<ab>/<file>/<width>px-<file>[.png] is a
    /// rendering of <file> at that width. Ask for 1280px rather than the original: originals can be
    /// tens of megabytes (or SVG/PDF/video), and Wikimedia only serves standard widths.
    private static func wikimedia(_ url: URL) -> [URL] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        var parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let thumb = parts.firstIndex(of: "thumb"), parts.count == thumb + 5,
              let width = parts[thumb + 4].firstMatch(of: /\d+px-/), width.output != "1280px-" else { return [] }
        parts[thumb + 4].replaceSubrange(width.range, with: "1280px-")
        components.percentEncodedPath = parts.joined(separator: "/")
        return components.url.map { [$0] } ?? []
    }

    /// i.ytimg.com/vi/<id>/<quality>.jpg (or vi_webp/…). Not every video has maxresdefault.
    private static func youtube(_ url: URL) -> [URL] {
        let parts = url.pathComponents
        guard parts.count >= 4, parts[1].hasPrefix("vi") else { return [] }
        return youtubeThumbnails(videoID: parts[2])
    }

    /// youtube.com/watch?v=<id>, youtube.com/shorts/<id>, youtu.be/<id>
    private static func youtubeVideo(_ url: URL) -> [URL] {
        let parts = url.pathComponents
        let id: String? = if url.host()?.lowercased() == "youtu.be" {
            parts.count >= 2 ? parts[1] : nil
        } else if parts.count >= 2, parts[1] == "watch" {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
        } else if parts.count >= 3, parts[1] == "shorts" {
            parts[2]
        } else {
            nil
        }
        guard let id else { return [] }
        return youtubeThumbnails(videoID: id)
    }

    private static func youtubeThumbnails(videoID id: String) -> [URL] {
        guard id.count == 11 else { return [] }
        return urls("https://i.ytimg.com/vi/\(id)/maxresdefault.jpg", "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }

    /// a.ltrbxd.com/resized/…-0-<w>-0-<h>-crop.jpg: posters (2:3) are also rendered at 1000×1500.
    private static func letterboxd(_ url: URL) -> [URL] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        let path = components.percentEncodedPath
        guard let match = path.firstMatch(of: /-0-(\d+)-0-(\d+)-crop\.(jpg|png)$/),
              let width = Int(match.1), let height = Int(match.2),
              width * 3 == height * 2, width < 1000 else { return [] }
        components.percentEncodedPath = path.replacingCharacters(in: match.range, with: "-0-1000-0-1500-crop.\(match.3)")
        return components.url.map { [$0] } ?? []
    }

    private static func urls(_ strings: String...) -> [URL] {
        strings.compactMap(URL.init(string:))
    }
}

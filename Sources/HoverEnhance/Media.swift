import Foundation

/// What a hovered element points at, worked out from URLs alone. Some sources need a network
/// lookup before they can be shown; `MediaFetcher` does that.
enum MediaSource: Sendable, Hashable {
    /// Image URLs, best first.
    case images([URL])
    /// A Reddit gallery post; its page lists the images.
    case redditGallery(id: String)
}

/// One thing a preview can show.
enum MediaItem: Sendable, Equatable {
    /// Image URLs, best first; the first that loads wins.
    case image([URL])
}

/// Resolved media: a single item, or an album.
struct Media: Sendable, Equatable {
    var items: [MediaItem]
}

/// Works out what to preview for a hover result.
enum MediaResolver {
    static func source(for info: HoverInfo) -> MediaSource? {
        // A link to a post outranks the thumbnail inside it: the post may hold more than one image.
        if let link = info.linkURL, let id = RedditGallery.id(fromLink: link) {
            return .redditGallery(id: id)
        }
        let images = imageCandidates(for: info)
        return images.isEmpty ? nil : .images(images)
    }

    /// Full-size image URLs for the hovered image or link, best first.
    static func imageCandidates(for info: HoverInfo) -> [URL] {
        var urls: [URL] = []
        // A link's target is usually the full image, so it outranks the thumbnail being shown.
        if let link = info.linkURL {
            urls += ImageRules.candidates(forLink: link)
        }
        if let image = info.imageURL, ImageRules.isFetchable(image) {
            urls += ImageRules.fullSize(of: image) + [image]
        }
        return urls.uniqued()
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

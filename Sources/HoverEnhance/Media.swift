import Foundation

/// What a hovered element points at, worked out from URLs alone. Some sources need a network
/// lookup before they can be shown; `MediaFetcher` does that.
enum MediaSource: Sendable, Hashable {
    /// Image URLs, best first.
    case images([URL])
    /// A file or HLS stream AVFoundation can play.
    case video(URL)
    /// A Reddit gallery post; its page lists the images.
    case redditGallery(id: String)
    case streamable(id: String)
    /// A post on X (Twitter): photos, a video, or a GIF.
    case tweet(id: String)
    /// A Bluesky post; `actor` is a handle or DID.
    case blueskyPost(actor: String, rkey: String)
    /// An Instagram post or reel, by shortcode.
    case instagram(code: String)
    /// A video played through its site's embeddable player.
    case embed(Embed)
    /// On YouTube itself: the creator behind a video or channel link.
    case youtubeChannel(YouTubeChannelRef)
    /// In Finder: a file or folder, in a window or on the desktop.
    case file(URL, onDesktop: Bool)
}

/// One thing a preview can show.
enum MediaItem: Sendable, Equatable {
    /// Image URLs, best first; the first that loads wins.
    case image([URL])
    /// A file or HLS stream AVFoundation can play, with its size when the site reports it.
    case video(URL, size: CGSize?)
    case embed(Embed)
    /// A card about a YouTube creator.
    case channel(YouTubeChannel)
    /// A card about a file or folder.
    case file(URL)
}

/// Resolved media: a single item, or an album.
struct Media: Sendable, Equatable {
    var items: [MediaItem]

    /// Without images and videos anywhere but the web, or nil if nothing is left. Lookups read what
    /// sites answer, and an answer mustn't point HoverEnhance at local files.
    func webOnly() -> Media? {
        func isWeb(_ url: URL) -> Bool { ["http", "https"].contains(url.scheme?.lowercased()) }
        let items = items.compactMap { item -> MediaItem? in
            switch item {
            case .image(let urls):
                let web = urls.filter(isWeb)
                return web.isEmpty ? nil : .image(web)
            case .video(let url, _):
                return isWeb(url) ? item : nil
            case .embed, .channel, .file:
                return item
            }
        }
        return items.isEmpty ? nil : Media(items: items)
    }
}

/// Works out what to preview for a hover result.
enum MediaResolver {
    /// Videos on a page smaller than this, such as looping thumbnails, still get a preview.
    static let smallestWatchableVideo = CGSize(width: 120, height: 90)

    static func source(for info: HoverInfo) -> MediaSource? {
        if let file = info.fileURL {
            // A card would cover Quick Look's panel, or the name being edited.
            return info.finderIsBusy ? nil : .file(file, onDesktop: info.fileIsOnDesktop)
        }
        // A video the page already shows under the cursor needs no preview, of it or of a still of it.
        if let video = info.videoFrame, video.width >= smallestWatchableVideo.width, video.height >= smallestWatchableVideo.height {
            return nil
        }
        var info = info
        // Only a local page may lead to local files. Browsers don't let web pages open them either:
        // besides reading the disk, a path under /net/<host> mounts that host's shares.
        if info.pageURL?.isFileURL != true {
            if info.linkURL?.isFileURL == true { info.linkURL = nil }
            if info.imageURL?.isFileURL == true { info.imageURL = nil }
        }
        // On YouTube itself, its thumbnails and hover previews are left alone. Text links to its
        // videos and channels get a card about the creator; text links elsewhere preview as usual.
        if YouTube.isYouTube(info.pageURL) {
            guard info.isOnText, let link = info.linkURL else { return nil }
            if let ref = YouTube.channelRef(fromLink: link) { return .youtubeChannel(ref) }
        }
        // A link to a post or video outranks the thumbnail inside it.
        if let link = info.linkURL, let source = SiteLinks.source(forLink: link) {
            return source
        }
        // Sites with their own players have their own hover previews; don't stack another on top.
        if let link = info.linkURL, let embed = Embed.from(link: link), !isOnSite(info.pageURL, of: embed.site) {
            return .embed(embed)
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

    private static func isOnSite(_ page: URL?, of site: Embed.Site) -> Bool {
        guard let host = page?.host()?.lowercased() else { return false }
        return site.domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

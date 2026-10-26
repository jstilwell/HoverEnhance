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
    /// A RedGIFs video, or an image and the gallery it's in.
    case redgifs(id: String)
    /// An Erome album, whose page lists its photos and videos.
    case erome(album: String)
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
    /// A link to a Wikipedia article, anywhere but Wikipedia.
    case wikipedia(WikipediaArticleRef)
    /// A link to a GitHub repository, issue, or pull request, anywhere but GitHub.
    case github(GitHubRef)
    /// In Finder: a file or folder, in a window or on the desktop.
    case file(URL, onDesktop: Bool)
    /// The Weather menu bar item, at `item`: its frame, for hanging the forecast under it.
    case weather(item: CGRect)
    /// The Wi-Fi menu bar item, at `item`: its frame, for hanging the network's details under it.
    case network(item: CGRect)
}

extension MediaSource {
    /// A post or gallery, which can hold several photos and videos.
    var isPost: Bool {
        switch self {
        case .redditGallery, .tweet, .blueskyPost, .instagram, .erome: true
        case .images, .video, .streamable, .redgifs, .embed, .youtubeChannel, .wikipedia, .github, .file, .weather, .network: false
        }
    }

    /// For a menu bar item: its frame, which the popup hangs under.
    var menuBarItem: CGRect? {
        switch self {
        case .weather(let item), .network(let item): item
        default: nil
        }
    }
}

/// One thing a preview can show.
enum MediaItem: Sendable, Equatable {
    /// Image URLs, best first; the first that loads wins.
    case image([URL])
    /// A file or HLS stream AVFoundation can play, with its size when the site reports it.
    case video(URL, size: CGSize?)
    case embed(Embed)
    /// A card about a YouTube creator, and the video when the link was to one.
    case channel(YouTubeChannel, video: YouTubeVideo?)
    /// A card about a Wikipedia article.
    case article(WikipediaArticle)
    /// A card about a GitHub repository, issue, or pull request.
    case github(GitHubCard)
    /// A card about a file or folder.
    case file(URL)
    /// The forecast, under the menu bar item at `item`.
    case weather(item: CGRect)
    /// The network's details, under the menu bar item at `item`.
    case network(item: CGRect)
}

/// Resolved media: a single item, or an album.
struct Media: Sendable, Equatable {
    var items: [MediaItem]

    /// The item showing `image`, matched by file name: sites serve one image at many sizes and
    /// addresses. Names too short to be an image's own, like "media", match nothing.
    func index(showing image: URL) -> Int? {
        let name = image.deletingPathExtension().lastPathComponent
        guard name.count >= 8 else { return nil }
        return items.firstIndex { item in
            guard case .image(let urls) = item else { return false }
            return urls.contains { $0.deletingPathExtension().lastPathComponent == name }
        }
    }

    /// Without images and videos anywhere but the web, or nil if nothing is left. Lookups read what
    /// sites answer, and an answer mustn't point HoverEnhance at local files or the local network.
    func webOnly() -> Media? {
        func isWeb(_ url: URL) -> Bool { ["http", "https"].contains(url.scheme?.lowercased()) && !LocalNetwork.contains(url) }
        let items = items.compactMap { item -> MediaItem? in
            switch item {
            case .image(let urls):
                let web = urls.filter(isWeb)
                return web.isEmpty ? nil : .image(web)
            case .video(let url, _):
                return isWeb(url) ? item : nil
            case .embed, .channel, .article, .github, .file, .weather, .network:
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
        if WeatherTrigger.matches(info), let frame = info.frame {
            return .weather(item: frame)
        }
        if SystemMenuExtra(info) == .network, let frame = info.frame {
            return .network(item: frame)
        }
        if let file = info.fileURL {
            // A card would cover Quick Look's panel, the name being edited, or an installer's Applications folder.
            return info.finderIsBusy || info.fileIsInInstaller ? nil : .file(file, onDesktop: info.fileIsOnDesktop)
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
        // Nor may a web page lead to this Mac's servers or the local network, as browsers keep it from
        // doing itself; see `LocalNetwork`.
        if info.pageURL?.isFileURL != true, !LocalNetwork.contains(info.pageURL) {
            if LocalNetwork.contains(info.linkURL) { info.linkURL = nil }
            if LocalNetwork.contains(info.imageURL) { info.imageURL = nil }
            if LocalNetwork.contains(info.postURL) { info.postURL = nil }
        }
        // On YouTube itself, its thumbnails and hover previews are left alone. Text links to its
        // videos and channels get a card about the creator; text links elsewhere preview as usual.
        if YouTube.isYouTube(info.pageURL) {
            guard info.isOnText, let link = info.linkURL else { return nil }
            if let ref = YouTube.channelRef(fromLink: link) { return .youtubeChannel(ref) }
        }
        // A link to an article or repository gets a card about it, unless what's hovered is an image to enlarge.
        if let link = info.linkURL, let card = cardSource(forLink: link, on: info.pageURL), info.isOnText || imageCandidates(for: info).isEmpty {
            return card
        }
        // A link to a post or video outranks the thumbnail inside it.
        if let link = info.linkURL, let source = SiteLinks.source(forLink: link) {
            return source
        }
        // A photo outside any link, as in Instagram's feed: its post, which may hold more photos.
        if info.linkURL == nil, let post = info.postURL, let source = SiteLinks.source(forLink: post) {
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

    /// Not on the site itself: Wikipedia has its own page previews, and GitHub its own hovercards.
    private static func cardSource(forLink link: URL, on page: URL?) -> MediaSource? {
        if let ref = Wikipedia.articleRef(fromLink: link), !Wikipedia.isWikipedia(page) { return .wikipedia(ref) }
        if let ref = GitHub.ref(fromLink: link), !GitHub.isGitHub(page) { return .github(ref) }
        return nil
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

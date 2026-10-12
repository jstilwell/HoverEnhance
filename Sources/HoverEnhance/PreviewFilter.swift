import Foundation

/// Sites with their own preview rules, each of which can be switched off in Settings.
enum MediaSite: String, CaseIterable, Identifiable, Codable, Sendable {
    case reddit, x, bluesky, instagram, streamable, youtube, vimeo, tiktok, twitch, imgur, wikimedia, letterboxd

    var id: Self { self }

    var name: String {
        switch self {
        case .reddit: "Reddit"
        case .x: "X (Twitter)"
        case .bluesky: "Bluesky"
        case .instagram: "Instagram"
        case .streamable: "Streamable"
        case .youtube: "YouTube"
        case .vimeo: "Vimeo"
        case .tiktok: "TikTok"
        case .twitch: "Twitch"
        case .imgur: "Imgur"
        case .wikimedia: "Wikipedia & Wikimedia"
        case .letterboxd: "Letterboxd"
        }
    }

    var detail: String {
        switch self {
        case .reddit: "Galleries, videos, and full-size images"
        case .x: "Photos and videos from posts"
        case .bluesky: "Photos and videos from posts, full-size images"
        case .instagram: "Photos, reels, and multi-photo posts"
        case .streamable: "Video clips"
        case .youtube: "Videos in YouTube's player, full-size thumbnails"
        case .vimeo: "Videos in Vimeo's player"
        case .tiktok: "Videos in TikTok's player"
        case .twitch: "Clips in Twitch's player"
        case .imgur: "Full-size images and GIF videos"
        case .wikimedia: "Large versions of article images"
        case .letterboxd: "Large posters"
        }
    }

    init?(host: String) {
        let host = host.lowercased()
        func on(_ domains: String...) -> Bool { domains.contains { host == $0 || host.hasSuffix("." + $0) } }
        if on("reddit.com", "redd.it", "redditmedia.com") { self = .reddit }
        else if on("x.com", "twitter.com", "twimg.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com") { self = .x }
        else if on("bsky.app") { self = .bluesky }
        else if on("instagram.com", "cdninstagram.com") { self = .instagram }
        else if on("streamable.com") { self = .streamable }
        else if on("youtube.com", "youtu.be", "ytimg.com") { self = .youtube }
        else if on("vimeo.com") { self = .vimeo }
        else if on("tiktok.com") { self = .tiktok }
        else if on("twitch.tv") { self = .twitch }
        else if on("imgur.com") { self = .imgur }
        else if on("wikimedia.org", "wikipedia.org") { self = .wikimedia }
        else if on("ltrbxd.com", "letterboxd.com") { self = .letterboxd }
        else { return nil }
    }
}

extension MediaSource {
    /// The site this comes from, or nil for images and videos anywhere else.
    var site: MediaSite? {
        switch self {
        case .images(let urls): urls.first?.host().flatMap(MediaSite.init(host:))
        case .video(let url): url.host().flatMap(MediaSite.init(host:))
        case .redditGallery: .reddit
        case .streamable: .streamable
        case .tweet: .x
        case .blueskyPost: .bluesky
        case .instagram: .instagram
        case .youtubeChannel: .youtube
        case .file, .weather: nil
        case .embed(let embed):
            switch embed.site {
            case .youtube: .youtube
            case .vimeo: .vimeo
            case .tiktok: .tiktok
            case .twitch: .twitch
            }
        }
    }
}

/// Which kinds of media and which sites to preview.
struct PreviewFilter: Sendable, Equatable {
    var images = true
    /// Off shows only the first item of a gallery or multi-photo post.
    var albums = true
    var videos = true
    var embeds = true
    var cards = true
    /// File cards in Finder.
    var files = true
    var filesOnDesktop = true
    /// Cards for folders, as opposed to files and packages such as apps.
    var folders = true
    /// The forecast under the Weather menu bar item.
    var weather = true
    var disabledSites: Set<MediaSite> = []

    /// Whether to look this source up at all.
    func allows(_ source: MediaSource) -> Bool {
        if let site = source.site, disabledSites.contains(site) { return false }
        switch source {
        case .images, .redditGallery: return images
        case .video, .streamable: return videos
        case .embed: return embeds
        case .youtubeChannel: return cards
        case .weather: return weather
        case .file(let url, let onDesktop):
            // Finder writes folder URLs with a trailing slash and packages, like apps, without.
            return files && (filesOnDesktop || !onDesktop) && (folders || !url.hasDirectoryPath)
        // Posts can hold photos or videos; what's turned off is dropped once they're looked up.
        case .tweet, .blueskyPost, .instagram: return images || videos
        }
    }

    /// The media without the kinds that are turned off, or nil if nothing is left.
    func apply(to media: Media) -> Media? {
        var items = media.items.filter { item in
            switch item {
            case .image: images
            case .video: videos
            case .embed: embeds
            case .channel: cards
            case .weather: weather
            case .file: files
            }
        }
        if !albums { items = Array(items.prefix(1)) }
        return items.isEmpty ? nil : Media(items: items)
    }
}

/// Whether previews that load from the network may happen in apps other than browsers. In a browser,
/// loading what a link points at does no more than the page itself could. Elsewhere it can give
/// something away: in Mail, a request to a sender's link tells them the message was read, and from where.
struct OtherAppsPolicy: Sendable, Equatable {
    /// Off, only browsers (and Finder's file cards, which don't touch the network) show previews.
    var enabled = false
    var skipsEmail = true
    /// Only links to the sites in Settings → Sites, not images and videos from anywhere.
    var knownSitesOnly = true
    /// Only while holding the activation key, so a preview is always asked for.
    var needsKey = false

    func allows(_ source: MediaSource, in app: AppKind, keyHeld: Bool) -> Bool {
        // Neither loads anything from what's hovered: Finder's cards read the disk, the forecast comes
        // from the provider chosen in Settings.
        switch source {
        case .file, .weather: return true
        default: break
        }
        if app == .browser { return true }
        guard enabled, !(skipsEmail && app == .email) else { return false }
        if knownSitesOnly, source.site == nil { return false }
        return !needsKey || keyHeld
    }
}

/// Websites the user asked for no previews on, by domain: "bank.example" covers its pages and its
/// subdomains' ("www.bank.example", "login.bank.example").
enum SkippedWebsites {
    /// The domain in what someone typed or pasted: "https://www.Bank.example/login" → "bank.example".
    /// Nil if there's no domain in it.
    static func domain(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !text.contains("://") { text = "https://" + text }
        guard var host = URL(string: text)?.host(percentEncoded: false), !host.isEmpty else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-:[]")
        guard host.contains(".") || host == "localhost", host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return host
    }

    static func contains(_ page: URL?, in domains: [String]) -> Bool {
        guard let host = page?.host(percentEncoded: false)?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

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
    var disabledSites: Set<MediaSite> = []

    /// Whether to look this source up at all.
    func allows(_ source: MediaSource) -> Bool {
        if let site = source.site, disabledSites.contains(site) { return false }
        switch source {
        case .images, .redditGallery: return images
        case .video, .streamable: return videos
        case .embed: return embeds
        case .youtubeChannel: return cards
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
            }
        }
        if !albums { items = Array(items.prefix(1)) }
        return items.isEmpty ? nil : Media(items: items)
    }
}

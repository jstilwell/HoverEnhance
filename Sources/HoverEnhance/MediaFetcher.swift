import Foundation

/// Turns a `MediaSource` into displayable media, doing whatever lookup the site needs.
actor MediaFetcher {
    private let session = URLSession(configuration: .default)
    /// Lookups, kept for a while: some sites' video links stop working after a few hours.
    private var looked: [MediaSource: (media: Media, time: Date)] = [:]
    private let lookupLifetime: TimeInterval = 30 * 60
    private var blueskyDIDs: [String: String] = [:]
    /// YouTube channel pages are about a megabyte, so each is read once per session.
    private var youtubeChannels: [URL: YouTubeChannel] = [:]

    func media(for source: MediaSource) async -> Media? {
        if let cached = looked[source], Date().timeIntervalSince(cached.time) < lookupLifetime { return cached.media }
        let lookedUp: Media?
        switch source {
        case .images(let urls):
            return Media(items: [.image(urls)])
        case .video(let url):
            return Media(items: [.video(url, size: nil)])
        case .embed(let embed):
            return Media(items: [.embed(embed)])
        case .file(let url, _):
            return Media(items: [.file(url)])
        case .redditGallery(let id):
            lookedUp = await redditGallery(id: id)
        case .streamable(let id):
            lookedUp = await data(at: SiteAPIs.streamableURL(id: id)).flatMap(SiteAPIs.streamable)
        case .tweet(let id):
            lookedUp = await data(at: SiteAPIs.tweetURL(id: id)).flatMap(SiteAPIs.tweet)
        case .blueskyPost(let actor, let rkey):
            lookedUp = await blueskyPost(actor: actor, rkey: rkey)
        case .instagram(let code):
            lookedUp = await instagram(code: code)
        case .youtubeChannel(let ref):
            lookedUp = await youtubeChannel(ref).map { Media(items: [.channel($0)]) }
        }
        // A lookup cut short, as when the cursor moves on, is no answer to keep.
        guard !Task.isCancelled else { return nil }
        let media = lookedUp?.webOnly()
        looked[source] = media.map { ($0, Date()) }
        return media
    }

    private func redditGallery(id: String) async -> Media? {
        let url = RedditGallery.pageURL(id: id)
        var urls = await data(at: url).map { RedditGallery.imageURLs(inPage: String(decoding: $0, as: UTF8.self)) } ?? []
        if urls.isEmpty {
            // Without a cookie from an earlier visit Reddit serves a JavaScript check instead of the
            // page; a real browser engine passes it.
            let carousel = await WebPageLoader.shared.html(at: url, selector: "gallery-carousel")
            urls = carousel.map(RedditGallery.imageURLs(inPage:)) ?? []
        }
        let items = urls.map { MediaItem.image((ImageRules.fullSize(of: $0) + [$0]).uniqued()) }
        return items.isEmpty ? nil : Media(items: items)
    }

    private func blueskyPost(actor: String, rkey: String) async -> Media? {
        var did = actor.hasPrefix("did:") ? actor : blueskyDIDs[actor]
        if did == nil, let url = SiteAPIs.blueskyHandleURL(actor) {
            did = await data(at: url).flatMap(SiteAPIs.blueskyDID)
            blueskyDIDs[actor] = did
        }
        guard let did, let url = SiteAPIs.blueskyPostURL(did: did, rkey: rkey) else { return nil }
        return await data(at: url).flatMap(SiteAPIs.blueskyPost)
    }

    private func instagram(code: String) async -> Media? {
        guard let page = await data(at: SiteAPIs.instagramEmbedURL(code: code)) else { return nil }
        if let media = SiteAPIs.instagram(embedPage: String(decoding: page, as: UTF8.self)) {
            return media
        }
        // A lone photo, whose embed page leaves its details out, or a post with embedding off: its
        // image (a reel's cover). Not when the page didn't arrive, or an album would stay one photo.
        return Media(items: [.image([SiteAPIs.instagramImageURL(code: code)])])
    }

    private func youtubeChannel(_ ref: YouTubeChannelRef) async -> YouTubeChannel? {
        var page = YouTube.channelPageURL(for: ref)
        if case .video(let id) = ref {
            page = await data(at: YouTube.oEmbedURL(videoID: id)).flatMap(YouTube.channelPageURL(fromOEmbed:))
        }
        guard let page else { return nil }
        if let known = youtubeChannels[page] { return known }
        guard let html = await data(at: page), let channel = YouTube.channel(inPage: String(decoding: html, as: UTF8.self)) else { return nil }
        youtubeChannels[page] = channel
        return channel
    }

    private func data(at url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url, delegate: LocalRedirectGuard.shared),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

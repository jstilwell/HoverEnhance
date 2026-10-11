import Foundation

/// Turns a `MediaSource` into displayable media, doing whatever lookup the site needs.
actor MediaFetcher {
    private let session = URLSession(configuration: .default)
    private var looked: [MediaSource: Media] = [:]
    private var blueskyDIDs: [String: String] = [:]

    func media(for source: MediaSource) async -> Media? {
        if let cached = looked[source] { return cached }
        let media: Media?
        switch source {
        case .images(let urls):
            return Media(items: [.image(urls)])
        case .video(let url):
            return Media(items: [.video(url, size: nil)])
        case .redditGallery(let id):
            media = await redditGallery(id: id)
        case .streamable(let id):
            media = await data(at: SiteAPIs.streamableURL(id: id)).flatMap(SiteAPIs.streamable)
        case .tweet(let id):
            media = await data(at: SiteAPIs.tweetURL(id: id)).flatMap(SiteAPIs.tweet)
        case .blueskyPost(let actor, let rkey):
            media = await blueskyPost(actor: actor, rkey: rkey)
        }
        if let media { looked[source] = media }
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

    private func data(at url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

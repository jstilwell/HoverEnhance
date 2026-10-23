import Foundation

/// Turns a `MediaSource` into displayable media, doing whatever lookup the site needs.
actor MediaFetcher {
    private let session: URLSession
    /// Lookups, kept for a while: some sites' video links stop working after a few hours.
    private var looked: [MediaSource: (media: Media, time: Date)] = [:]
    private let lookupLifetime: TimeInterval = 30 * 60
    /// Lookups that came back empty, kept briefly, so hovering the same link again doesn't ask again at
    /// once, or load Reddit's page in a web view again.
    private var missed: [MediaSource: (failed: Bool, time: Date)] = [:]
    private let missLifetime: TimeInterval = 60

    enum Lookup: Sendable, Equatable {
        case found(Media)
        /// The site answered with nothing to show, as for a post without photos or video.
        case nothing
        /// The site didn't answer, or refused.
        case failed
    }

    /// Whether any of one lookup's requests went unanswered.
    private final class Requests {
        var failed = false
    }
    private var blueskyDIDs: [String: String] = [:]
    private var redgifsToken: (value: String, time: Date)?
    /// RedGIFs' tokens last a day; one is replaced a little before then.
    private let redgifsTokenLifetime: TimeInterval = 23 * 60 * 60
    /// YouTube channel pages are about a megabyte, so each is read once per session.
    private var youtubeChannels: [URL: YouTubeChannel] = [:]
    /// Letterboxd's posters, by film slug: rows of them on cards for people and lists repeat.
    private var letterboxdPosters: [String: URL] = [:]

    init(configuration: URLSessionConfiguration = MediaFetcher.configuration()) {
        session = URLSession(configuration: configuration)
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        // A spinner is up while a lookup runs; the defaults would leave it there a minute or more.
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return configuration
    }

    func lookUp(_ source: MediaSource) async -> Lookup {
        if let cached = looked[source], Date().timeIntervalSince(cached.time) < lookupLifetime { return .found(cached.media) }
        if let miss = missed[source], Date().timeIntervalSince(miss.time) < missLifetime { return miss.failed ? .failed : .nothing }
        let requests = Requests()
        let lookedUp: Media?
        switch source {
        case .images(let urls):
            return .found(Media(items: [.image(urls)]))
        case .video(let url):
            return .found(Media(items: [.video(url, size: nil)]))
        case .embed(let embed):
            return .found(Media(items: [.embed(embed)]))
        case .file(let url, _):
            return .found(Media(items: [.file(url)]))
        case .weather(let item):
            return .found(Media(items: [.weather(item: item)]))
        case .network(let item):
            return .found(Media(items: [.network(item: item)]))
        case .redditGallery(let id):
            lookedUp = await redditGallery(id: id, requests)
        case .streamable(let id):
            lookedUp = await data(at: SiteAPIs.streamableURL(id: id), requests).flatMap(SiteAPIs.streamable)
        case .redgifs(let id):
            lookedUp = await redgifs(id: id, requests)
        case .erome(let album):
            lookedUp = await data(at: SiteAPIs.eromeAlbumURL(album), requests).flatMap { SiteAPIs.erome(albumPage: String(decoding: $0, as: UTF8.self)) }
        case .tweet(let id):
            lookedUp = await data(at: SiteAPIs.tweetURL(id: id), requests).flatMap(SiteAPIs.tweet)
        case .blueskyPost(let actor, let rkey):
            lookedUp = await blueskyPost(actor: actor, rkey: rkey, requests)
        case .instagram(let code):
            lookedUp = await instagram(code: code, requests)
        case .wikipedia(let ref):
            guard let url = Wikipedia.summaryURL(for: ref) else { return .nothing }
            lookedUp = await data(at: url, headers: ["User-Agent": Wikipedia.userAgent], requests)
                .flatMap(Wikipedia.article).map { Media(items: [.article($0)]) }
        case .github(let ref):
            lookedUp = await data(at: GitHub.apiURL(for: ref), headers: GitHub.headers, requests)
                .flatMap { GitHub.card($0, for: ref) }.map { Media(items: [.github($0)]) }
        case .youtubeChannel(let ref):
            lookedUp = await youtubeCard(ref, requests).map { Media(items: [.channel($0.channel, video: $0.video)]) }
        case .letterboxd(let ref):
            lookedUp = await letterboxdCard(ref, requests).map { Media(items: [.letterboxd($0)]) }
        }
        // A lookup cut short, as when the cursor moves on, is no answer to keep.
        guard !Task.isCancelled else { return .nothing }
        if let media = lookedUp?.webOnly() {
            looked[source] = (media, Date())
            missed[source] = nil
            return .found(media)
        }
        missed = missed.filter { Date().timeIntervalSince($0.value.time) < missLifetime }
        missed[source] = (requests.failed, Date())
        return requests.failed ? .failed : .nothing
    }

    private func redditGallery(id: String, _ requests: Requests) async -> Media? {
        let url = RedditGallery.pageURL(id: id)
        var urls = await data(at: url, requests).map { RedditGallery.imageURLs(inPage: String(decoding: $0, as: UTF8.self)) } ?? []
        if urls.isEmpty {
            // Without a cookie from an earlier visit Reddit serves a JavaScript check instead of the
            // page; a real browser engine passes it. Whether that answers decides whether this failed.
            let carousel = await WebPageLoader.shared.html(at: url, selector: "gallery-carousel")
            requests.failed = carousel == nil
            urls = carousel.map(RedditGallery.imageURLs(inPage:)) ?? []
        }
        let items = urls.map { MediaItem.image((ImageRules.fullSize(of: $0) + [$0]).uniqued()) }
        return items.isEmpty ? nil : Media(items: items)
    }

    private func redgifs(id: String, _ requests: Requests) async -> Media? {
        guard let gif = await redgifsData(at: SiteAPIs.redgifsGifURL(id: id), requests).flatMap(SiteAPIs.redgifsGif) else { return nil }
        // An image in a gallery shows the whole gallery, or itself when that can't be read.
        guard let url = gif.gallery.flatMap(SiteAPIs.redgifsGalleryURL) else { return gif.media }
        let gallery = await redgifsData(at: url, Requests()).flatMap(SiteAPIs.redgifsGallery)
        return gallery ?? gif.media
    }

    /// RedGIFs' API answers only requests that carry a token. One that stops working, as when the Mac's address changes,
    /// is replaced once.
    private func redgifsData(at url: URL, _ requests: Requests) async -> Data? {
        for attempt in 0..<2 {
            if attempt > 0 || redgifsToken.map({ Date().timeIntervalSince($0.time) >= redgifsTokenLifetime }) ?? true {
                guard let token = await data(at: SiteAPIs.redgifsTokenURL, requests).flatMap(SiteAPIs.redgifsToken) else { return nil }
                redgifsToken = (token, Date())
            }
            guard let token = redgifsToken?.value else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await session.data(for: request, delegate: LocalRedirectGuard.shared) else { break }
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: return data
            case 401: redgifsToken = nil
            default: requests.failed = true; return nil
            }
        }
        requests.failed = true
        return nil
    }

    private func blueskyPost(actor: String, rkey: String, _ requests: Requests) async -> Media? {
        var did = actor.hasPrefix("did:") ? actor : blueskyDIDs[actor]
        if did == nil, let url = SiteAPIs.blueskyHandleURL(actor) {
            did = await data(at: url, requests).flatMap(SiteAPIs.blueskyDID)
            blueskyDIDs[actor] = did
        }
        guard let did, let url = SiteAPIs.blueskyPostURL(did: did, rkey: rkey) else { return nil }
        return await data(at: url, requests).flatMap(SiteAPIs.blueskyPost)
    }

    private func instagram(code: String, _ requests: Requests) async -> Media? {
        guard let page = await data(at: SiteAPIs.instagramEmbedURL(code: code), requests) else { return nil }
        if let media = SiteAPIs.instagram(embedPage: String(decoding: page, as: UTF8.self)) {
            return media
        }
        // A lone photo, whose embed page leaves its details out, or a post with embedding off: its
        // image (a reel's cover). Not when the page didn't arrive, or an album would stay one photo.
        return Media(items: [.image([SiteAPIs.instagramImageURL(code: code)])])
    }

    /// The creator behind a link, and the video when the link is to one.
    private func youtubeCard(_ ref: YouTubeChannelRef, _ requests: Requests) async -> (channel: YouTubeChannel, video: YouTubeVideo?)? {
        var page = YouTube.channelPageURL(for: ref)
        var video: YouTubeVideo?
        if case .video(let id) = ref {
            // The video's page has its numbers and names its channel. When it can't be read, the card is
            // the channel's alone, found through oEmbed.
            if let html = await data(at: YouTube.watchPageURL(videoID: id), requests),
               let watched = YouTube.video(inPage: String(decoding: html, as: UTF8.self)) {
                video = watched.video
                page = watched.channelPage
            }
            if page == nil {
                page = await data(at: YouTube.oEmbedURL(videoID: id), requests).flatMap(YouTube.channelPageURL(fromOEmbed:))
            }
        }
        guard let page else { return nil }
        if let known = youtubeChannels[page] { return (known, video) }
        guard let html = await data(at: page, requests), let channel = YouTube.channel(inPage: String(decoding: html, as: UTF8.self)) else { return nil }
        youtubeChannels[page] = channel
        return (channel, video)
    }

    /// The card for a Letterboxd page, with the posters it shows, which its page leaves for scripts to fetch.
    private func letterboxdCard(_ ref: LetterboxdRef, _ requests: Requests) async -> LetterboxdCard? {
        guard let page = await letterboxdPage(ref.pageURL, requests), let card = Letterboxd.card(inPage: page.html, at: page.url) else { return nil }
        switch card {
        case .film:
            return card
        case .review(var review):
            review.poster = await letterboxdPoster(review.filmSlug)
            return .review(review)
        case .person(var person):
            person.films = await withPosters(person.films)
            return .person(person)
        case .list(var list):
            list.films = await withPosters(list.films)
            return .list(list)
        }
    }

    /// A Letterboxd page, and where it was after any redirect, as from a short link. Cloudflare answers some
    /// of its pages, such as a member's later viewings of a film, with a check only a browser engine passes.
    private func letterboxdPage(_ url: URL, _ requests: Requests) async -> (html: String, url: URL)? {
        guard let (data, response) = try? await session.data(from: url, delegate: LocalRedirectGuard.shared),
              let http = response as? HTTPURLResponse, let final = http.url else {
            requests.failed = true
            return nil
        }
        if http.statusCode == 200 { return (String(decoding: data, as: UTF8.self), final) }
        // Only Letterboxd's own pages go to the web view, which follows redirects without the guard.
        guard http.statusCode == 403, Letterboxd.isLetterboxd(final),
              let page = await WebPageLoader.shared.page(at: final, once: #"meta[property="og:url"]"#) else {
            requests.failed = true
            return nil
        }
        return (page.html, page.url ?? final)
    }

    private func withPosters(_ films: [LetterboxdPoster]) async -> [LetterboxdPoster] {
        let images = await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, film) in films.enumerated() {
                group.addTask { (index, await self.letterboxdPoster(film.slug)) }
            }
            var images: [Int: URL] = [:]
            for await (index, image) in group { images[index] = image }
            return images
        }
        return films.enumerated().map { index, film in
            var film = film
            film.image = images[index]
            return film
        }
    }

    /// A film's poster, or nil when it has none to show, or can't be had: the card goes without.
    private func letterboxdPoster(_ slug: String) async -> URL? {
        if let known = letterboxdPosters[slug] { return known }
        guard let url = Letterboxd.posterURL(film: slug), let poster = await data(at: url, Requests()).flatMap(Letterboxd.poster) else { return nil }
        letterboxdPosters[slug] = poster
        return poster
    }

    private func data(at url: URL, headers: [String: String] = [:], _ requests: Requests) async -> Data? {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        guard let (data, response) = try? await session.data(for: request, delegate: LocalRedirectGuard.shared),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            requests.failed = true
            return nil
        }
        return data
    }
}

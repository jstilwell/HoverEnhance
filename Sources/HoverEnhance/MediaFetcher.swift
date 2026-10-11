import Foundation

/// Turns a `MediaSource` into displayable media, doing whatever lookup the site needs.
actor MediaFetcher {
    private let session = URLSession(configuration: .default)
    private var looked: [MediaSource: Media] = [:]

    func media(for source: MediaSource) async -> Media? {
        if let cached = looked[source] { return cached }
        let media: Media?
        switch source {
        case .images(let urls):
            return Media(items: [.image(urls)])
        case .redditGallery(let id):
            media = await redditGallery(id: id)
        }
        if let media { looked[source] = media }
        return media
    }

    private func redditGallery(id: String) async -> Media? {
        let url = RedditGallery.pageURL(id: id)
        var urls = await text(at: url).map(RedditGallery.imageURLs(inPage:)) ?? []
        if urls.isEmpty {
            // Without a cookie from an earlier visit Reddit serves a JavaScript check instead of the
            // page; a real browser engine passes it.
            let carousel = await WebPageLoader.shared.html(at: url, selector: "gallery-carousel")
            urls = carousel.map(RedditGallery.imageURLs(inPage:)) ?? []
        }
        let items = urls.map { MediaItem.image((ImageRules.fullSize(of: $0) + [$0]).uniqued()) }
        return items.isEmpty ? nil : Media(items: items)
    }

    private func text(at url: URL) async -> String? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

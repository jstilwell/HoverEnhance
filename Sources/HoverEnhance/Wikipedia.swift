import Foundation

/// A Wikipedia article a link points at, in any language's Wikipedia.
struct WikipediaArticleRef: Sendable, Hashable {
    /// The subdomain naming the wiki: "en", "de", "zh-yue".
    let language: String
    /// As in the link's path, still percent-encoded: "Matterhorn", "Z%C3%BCrich".
    let title: String
}

/// What a card shows about an article: Wikipedia's own summary of it, as in its page previews.
struct WikipediaArticle: Sendable, Equatable {
    let title: String
    /// Wikidata's short description: "Mountain in the Swiss and Italian Alps".
    let description: String?
    /// The article's first paragraphs, as plain text.
    let extract: String
    let image: URL?
    let imageSize: CGSize?
    let url: URL
    let language: String
    let isRightToLeft: Bool
}

enum Wikipedia {
    static func isWikipedia(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "wikipedia.org" || host.hasSuffix(".wikipedia.org")
    }

    /// <language>.wikipedia.org/wiki/<title>, and the mobile site's <language>.m.wikipedia.org.
    static func articleRef(fromLink url: URL) -> WikipediaArticleRef? {
        guard ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host()?.lowercased(),
              host.hasSuffix(".wikipedia.org") else { return nil }
        let labels = host.dropLast(".wikipedia.org".count).split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 1 || (labels.count == 2 && labels[1] == "m"), let language = labels.first,
              !language.isEmpty, language != "www", language.allSatisfy({ $0.isASCII && ($0.isLowercase || $0 == "-") }) else { return nil }
        let path = url.path(percentEncoded: true)
        guard path.hasPrefix("/wiki/") else { return nil }
        let title = String(path.dropFirst("/wiki/".count))
        // A title is one path segment; a slash in one comes encoded.
        guard !title.isEmpty, !title.contains("/") else { return nil }
        return WikipediaArticleRef(language: String(language), title: title)
    }

    static func summaryURL(for ref: WikipediaArticleRef) -> URL? {
        URL(string: "https://\(ref.language).wikipedia.org/api/rest_v1/page/summary/\(ref.title)")
    }

    /// Wikimedia asks scripted clients to say who they are.
    static let userAgent = "HoverEnhance/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") (https://hoverenhance.com)"

    /// The summary Wikipedia's page previews show. Nil for pages other than articles, such as a file's or
    /// a category's.
    /// An image in a summary.
    struct Image: Decodable, Equatable {
        let source: String
        let width: Double?
        let height: Double?
    }

    static func article(_ data: Data) -> WikipediaArticle? {
        struct Namespace: Decodable { let id: Int }
        struct Links: Decodable {
            struct Page: Decodable { let page: String }
            let desktop: Page
        }
        struct Summary: Decodable {
            let title: String
            let description: String?
            let extract: String?
            let thumbnail: Image?
            let originalimage: Image?
            let namespace: Namespace?
            let content_urls: Links
            let lang: String?
            let dir: String?
        }
        guard let summary = try? JSONDecoder().decode(Summary.self, from: data), summary.namespace?.id ?? 0 == 0,
              let url = URL(string: summary.content_urls.desktop.page) else { return nil }
        let image = cardImage(thumbnail: summary.thumbnail, original: summary.originalimage)
        return WikipediaArticle(
            title: summary.title,
            description: summary.description.flatMap { $0.isEmpty ? nil : $0 },
            extract: summary.extract ?? "",
            image: image.flatMap { URL(string: $0.source) },
            imageSize: image.flatMap { image in image.width.flatMap { width in image.height.map { CGSize(width: width, height: $0) } } },
            url: url,
            language: summary.lang ?? "",
            isRightToLeft: summary.dir == "rtl"
        )
    }

    /// Twice the card's width. The summary's thumbnail is 330 pixels wide, a rendering of the original at
    /// one of the widths Wikimedia serves.
    static let cardImageWidth = 960

    /// The summary's image at a size for the card: the original when it's a small enough photo, or else
    /// the thumbnail asked for at `cardImageWidth`, which Wikimedia only renders from larger originals.
    static func cardImage(thumbnail: Image?, original: Image?) -> Image? {
        guard let thumbnail else { return original }
        guard let original, let width = original.width, let height = original.height, width > 0 else { return thumbnail }
        if width <= Double(cardImageWidth) {
            let ext = URL(string: original.source)?.pathExtension.lowercased() ?? ""
            return ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) ? original : thumbnail
        }
        guard let match = thumbnail.source.firstMatch(of: /\/\d+px-/) else { return thumbnail }
        return Image(source: thumbnail.source.replacingCharacters(in: match.range, with: "/\(cardImageWidth)px-"),
                     width: Double(cardImageWidth), height: (height * Double(cardImageWidth) / width).rounded())
    }
}

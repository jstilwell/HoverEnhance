import Foundation
import Testing
@testable import HoverEnhance

struct WikipediaLinkTests {
    private func ref(_ string: String) -> WikipediaArticleRef? {
        Wikipedia.articleRef(fromLink: URL(string: string)!)
    }

    @Test func articlesInAnyLanguage() {
        #expect(ref("https://en.wikipedia.org/wiki/Matterhorn") == WikipediaArticleRef(language: "en", title: "Matterhorn"))
        #expect(ref("https://de.m.wikipedia.org/wiki/Z%C3%BCrich#Geschichte") == WikipediaArticleRef(language: "de", title: "Z%C3%BCrich"))
        #expect(ref("https://zh-yue.wikipedia.org/wiki/%E9%A6%99%E6%B8%AF") == WikipediaArticleRef(language: "zh-yue", title: "%E9%A6%99%E6%B8%AF"))
        #expect(ref("https://en.wikipedia.org/wiki/AC/DC") == nil, "an unencoded slash isn't one title")
        #expect(ref("https://en.wikipedia.org/wiki/AC%2FDC") == WikipediaArticleRef(language: "en", title: "AC%2FDC"))
    }

    @Test func otherPagesAreNotArticles() {
        #expect(ref("https://www.wikipedia.org/") == nil)
        #expect(ref("https://en.wikipedia.org/w/index.php?title=Matterhorn") == nil)
        #expect(ref("https://en.wikipedia.org/wiki/") == nil)
        #expect(ref("https://upload.wikimedia.org/wikipedia/commons/6/60/Matterhorn.jpg") == nil)
        #expect(ref("https://en.wikipedia.org.example.com/wiki/Matterhorn") == nil)
        #expect(ref("https://commons.m.m.wikipedia.org/wiki/Matterhorn") == nil)
    }

    @Test func summaryURL() {
        #expect(Wikipedia.summaryURL(for: WikipediaArticleRef(language: "de", title: "Z%C3%BCrich"))
            == URL(string: "https://de.wikipedia.org/api/rest_v1/page/summary/Z%C3%BCrich"))
    }
}

struct WikipediaSummaryTests {
    private let matterhorn = """
    {"type": "standard", "title": "Matterhorn", "namespace": {"id": 0, "text": ""}, "lang": "en", "dir": "ltr",
     "description": "Mountain in the Swiss and Italian Alps",
     "extract": "The Matterhorn is a mountain of the Alps, straddling the main watershed and border between Italy and Switzerland.",
     "thumbnail": {"source": "https://thumb.wikimedia.org/wikipedia/commons/thumb/6/60/Matterhorn.jpg/330px-Matterhorn.jpg?utm_source=en.wikipedia.org", "width": 330, "height": 220},
     "originalimage": {"source": "https://upload.wikimedia.org/wikipedia/commons/6/60/Matterhorn.jpg", "width": 3000, "height": 2000},
     "content_urls": {"desktop": {"page": "https://en.wikipedia.org/wiki/Matterhorn"}}}
    """

    @Test func anArticle() throws {
        let article = try #require(Wikipedia.article(Data(matterhorn.utf8)))
        #expect(article.title == "Matterhorn")
        #expect(article.description == "Mountain in the Swiss and Italian Alps")
        #expect(article.extract.hasPrefix("The Matterhorn is"))
        #expect(article.url == URL(string: "https://en.wikipedia.org/wiki/Matterhorn"))
        #expect(article.language == "en")
        #expect(!article.isRightToLeft)
        // Asked for at the card's size, from the large original.
        #expect(article.image == URL(string: "https://thumb.wikimedia.org/wikipedia/commons/thumb/6/60/Matterhorn.jpg/960px-Matterhorn.jpg?utm_source=en.wikipedia.org"))
        #expect(article.imageSize == CGSize(width: 960, height: 640))
    }

    @Test func pagesOtherThanArticlesHaveNoCard() {
        let file = matterhorn.replacingOccurrences(of: #""namespace": {"id": 0"#, with: #""namespace": {"id": 6"#)
        #expect(Wikipedia.article(Data(file.utf8)) == nil)
        #expect(Wikipedia.article(Data(#"{"type": "https://mediawiki.org/wiki/HyperSwitch/errors/not_found"}"#.utf8)) == nil)
    }

    @Test func imagesForTheCard() {
        typealias Image = Wikipedia.Image
        let thumbnail = Image(source: "https://thumb.wikimedia.org/a/thumb/x/y/A.png/330px-A.png", width: 330, height: 330)
        // A small photo is shown as it is.
        let small = Image(source: "https://upload.wikimedia.org/a/x/y/A.png", width: 500, height: 500)
        #expect(Wikipedia.cardImage(thumbnail: thumbnail, original: small) == small)
        // A small drawing comes as the thumbnail, a PNG rendering of it.
        let drawing = Image(source: "https://upload.wikimedia.org/a/x/y/A.svg", width: 500, height: 500)
        #expect(Wikipedia.cardImage(thumbnail: thumbnail, original: drawing) == thumbnail)
        #expect(Wikipedia.cardImage(thumbnail: thumbnail, original: nil) == thumbnail)
        #expect(Wikipedia.cardImage(thumbnail: nil, original: nil) == nil)
    }
}

struct WikipediaHoverRuleTests {
    private func info(link: String, onText: Bool, image: String? = nil, page: String = "https://news.example/story") -> HoverInfo {
        var info = HoverInfo(pid: 1, appKind: .browser)
        info.pageURL = URL(string: page)
        info.linkURL = URL(string: link)
        info.imageURL = image.flatMap(URL.init(string:))
        info.isOnText = onText
        return info
    }

    private let matterhorn = WikipediaArticleRef(language: "en", title: "Matterhorn")

    @Test func textLinksGetACard() {
        #expect(MediaResolver.source(for: info(link: "https://en.wikipedia.org/wiki/Matterhorn", onText: true)) == .wikipedia(matterhorn))
    }

    @Test func anImageInTheLinkIsEnlargedInstead() {
        let image = "https://upload.wikimedia.org/wikipedia/commons/thumb/6/60/Matterhorn.jpg/250px-Matterhorn.jpg"
        #expect(MediaResolver.source(for: info(link: "https://en.wikipedia.org/wiki/Matterhorn", onText: false, image: image))
            == .images([URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/6/60/Matterhorn.jpg/1280px-Matterhorn.jpg")!, URL(string: image)!]))
        #expect(MediaResolver.source(for: info(link: "https://en.wikipedia.org/wiki/Matterhorn", onText: false)) == .wikipedia(matterhorn))
    }

    @Test func wikipediaHasItsOwnPreviews() {
        #expect(MediaResolver.source(for: info(link: "https://en.wikipedia.org/wiki/Matterhorn", onText: true,
                                               page: "https://en.wikipedia.org/wiki/Alps")) == nil)
    }

    @Test func cardsCanBeTurnedOff() {
        #expect(!PreviewFilter(cards: false).allows(.wikipedia(matterhorn)))
        #expect(!PreviewFilter(disabledSites: [.wikimedia]).allows(.wikipedia(matterhorn)))
        #expect(PreviewFilter(cards: false).apply(to: Media(items: [.article(WikipediaArticle(
            title: "A", description: nil, extract: "", image: nil, imageSize: nil, url: URL(string: "https://en.wikipedia.org/wiki/A")!,
            language: "en", isRightToLeft: false))])) == nil)
    }
}

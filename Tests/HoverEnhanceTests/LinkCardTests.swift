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

struct GitHubLinkTests {
    private func ref(_ string: String) -> GitHubRef? {
        GitHub.ref(fromLink: URL(string: string)!)
    }

    @Test func reposIssuesAndPulls() {
        #expect(ref("https://github.com/swiftlang/swift") == .repo(owner: "swiftlang", name: "swift"))
        #expect(ref("https://github.com/swiftlang/swift.git") == .repo(owner: "swiftlang", name: "swift"))
        #expect(ref("https://github.com/sveltejs/svelte/tree/main/packages") == .repo(owner: "sveltejs", name: "svelte"))
        #expect(ref("https://github.com/vercel/next.js/issues") == .repo(owner: "vercel", name: "next.js"))
        #expect(ref("https://github.com/swiftlang/swift/issues/80000#issuecomment-1") == .issue(owner: "swiftlang", name: "swift", number: 80000))
        #expect(ref("https://github.com/swiftlang/swift/pull/70000/files") == .pull(owner: "swiftlang", name: "swift", number: 70000))
    }

    @Test func otherPagesAreNotRepos() {
        #expect(ref("https://github.com/swiftlang") == nil)
        #expect(ref("https://github.com/settings/profile") == nil)
        #expect(ref("https://github.com/orgs/swiftlang/repositories") == nil)
        #expect(ref("https://github.com/a/..") == nil)
        #expect(ref("https://gist.github.com/someone/abc123") == nil)
        #expect(ref("https://github.com/swiftlang/swift/pull/99999999999999") == .repo(owner: "swiftlang", name: "swift"))
    }

    @Test func apiURLs() {
        #expect(GitHub.apiURL(for: .pull(owner: "a", name: "b.c", number: 7)) == URL(string: "https://api.github.com/repos/a/b.c/pulls/7"))
        #expect(GitHub.apiURL(for: .issue(owner: "a", name: "b", number: 7)) == URL(string: "https://api.github.com/repos/a/b/issues/7"))
    }
}

/// Fixtures are trimmed copies of the API's answers.
struct GitHubAnswerTests {
    private let repo = .repo(owner: "swiftlang", name: "swift") as GitHubRef

    @Test func aRepository() throws {
        let json = """
        {"full_name": "swiftlang/swift", "html_url": "https://github.com/swiftlang/swift", "description": "The Swift Programming Language",
         "stargazers_count": 70513, "forks_count": 10856, "language": "Swift", "topics": [], "pushed_at": "2026-10-19T15:18:05Z",
         "archived": false, "fork": false, "license": {"spdx_id": "Apache-2.0"},
         "owner": {"login": "swiftlang", "type": "Organization", "avatar_url": "https://avatars.githubusercontent.com/u/42816656?v=4"}}
        """
        guard case .repo(let card) = try #require(GitHub.card(Data(json.utf8), for: repo)) else { Issue.record("not a repo"); return }
        #expect(card.fullName == "swiftlang/swift")
        #expect(card.stars == 70513)
        #expect(card.license == "Apache-2.0")
        #expect(card.isOrganization)
        #expect(card.pushed == ISO8601DateFormatter().date(from: "2026-10-19T15:18:05Z"))
        #expect(card.url == URL(string: "https://github.com/swiftlang/swift"))
    }

    @Test func licensesGitHubCouldntNameAreLeftOut() throws {
        let json = """
        {"full_name": "a/b", "html_url": "https://github.com/a/b", "stargazers_count": 1, "forks_count": 0,
         "license": {"spdx_id": "NOASSERTION"}, "owner": {"login": "a", "type": "User"}}
        """
        guard case .repo(let card) = try #require(GitHub.card(Data(json.utf8), for: .repo(owner: "a", name: "b"))) else { return }
        #expect(card.license == nil)
        #expect(!card.isOrganization)
    }

    @Test func pullRequestsFromThePullsAPI() throws {
        let json = """
        {"number": 70000, "title": "GenericSpecializer: support specializing typed throws", "html_url": "https://github.com/swiftlang/swift/pull/70000",
         "state": "closed", "draft": false, "merged_at": "2023-11-27T11:39:24Z", "user": {"login": "eeckstein"}, "created_at": "2023-11-22T11:05:31Z",
         "body": "This means to support specializing functions with indirect error results.", "labels": [{"name": "swift", "color": "F05138"}],
         "comments": 3, "additions": 437, "deletions": 107, "changed_files": 12}
        """
        guard case .issue(let pull) = try #require(GitHub.card(Data(json.utf8), for: .pull(owner: "swiftlang", name: "swift", number: 70000))) else { return }
        #expect(pull.isPull)
        #expect(pull.state == .merged)
        #expect(pull.repo == "swiftlang/swift")
        #expect(pull.additions == 437 && pull.deletions == 107 && pull.changedFiles == 12)
        #expect(pull.labels == [GitHubIssue.Label(name: "swift", color: "F05138")])
    }

    @Test func issueStates() throws {
        func state(_ fields: String, pull: Bool = false) throws -> GitHubIssue.State? {
            let json = #"{"number": 1, "title": "T", "html_url": "https://github.com/a/b/\#(pull ? "pull" : "issues")/1", \#(fields)}"#
            guard case .issue(let issue) = try #require(GitHub.card(Data(json.utf8), for: .issue(owner: "a", name: "b", number: 1))) else { return nil }
            return issue.state
        }
        #expect(try state(#""state": "open""#) == .open)
        #expect(try state(#""state": "closed", "state_reason": "completed""#) == .closed)
        #expect(try state(#""state": "closed", "state_reason": "not_planned""#) == .notPlanned)
        // A pull request reached through the issues API.
        #expect(try state(#""state": "open", "draft": true, "pull_request": {"merged_at": null}"#, pull: true) == .draft)
        #expect(try state(#""state": "closed", "pull_request": {"merged_at": "2023-11-27T11:39:24Z"}"#, pull: true) == .merged)
        #expect(try state(#""state": "closed", "pull_request": {"merged_at": null}"#, pull: true) == .closed)
    }

    @Test func excerptsAreThePlainTextOfTheDescription() {
        let body = """
        <!-- Thanks for filing! Please fill in the template. -->
        ## What happened

        The **build** fails with `swift build` on [macOS](https://apple.com). ![shot](https://x/y.png)
        - see <details>logs</details>
        """
        #expect(GitHub.excerpt(of: body) == "What happened The build fails with swift build on macOS. see logs")
        #expect(GitHub.excerpt(of: String(repeating: "word ", count: 100), limit: 20) == "word word word word…")
    }

    @Test func counts() {
        #expect(GitHubFormat.count(999) == "999")
        #expect(GitHubFormat.count(1000) == "1k")
        #expect(GitHubFormat.count(70513) == "70.5k")
        #expect(GitHubFormat.count(1_500_000) == "1.5m")
    }
}

struct GitHubHoverRuleTests {
    private func info(link: String, page: String = "https://news.ycombinator.com/") -> HoverInfo {
        var info = HoverInfo(pid: 1, appKind: .browser)
        info.pageURL = URL(string: page)
        info.linkURL = URL(string: link)
        info.isOnText = true
        return info
    }

    @Test func linksGetACard() {
        #expect(MediaResolver.source(for: info(link: "https://github.com/swiftlang/swift")) == .github(.repo(owner: "swiftlang", name: "swift")))
    }

    @Test func gitHubHasItsOwnHovercards() {
        #expect(MediaResolver.source(for: info(link: "https://github.com/swiftlang/swift", page: "https://github.com/trending")) == nil)
    }

    @Test func cardsCanBeTurnedOff() {
        #expect(!PreviewFilter(cards: false).allows(.github(.repo(owner: "a", name: "b"))))
        #expect(!PreviewFilter(disabledSites: [.github]).allows(.github(.repo(owner: "a", name: "b"))))
    }
}

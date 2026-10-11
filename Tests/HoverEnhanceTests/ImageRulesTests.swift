import Foundation
import Testing
@testable import HoverEnhance

/// Rule examples use real URLs whose rewrites were checked against the live servers, except Reddit
/// and Imgur, which block scripted requests.
struct ImageRulesTests {
    private func fullSize(_ string: String) -> [String] {
        ImageRules.fullSize(of: URL(string: string)!).map(\.absoluteString)
    }

    private func fromLink(_ string: String) -> [String] {
        ImageRules.candidates(forLink: URL(string: string)!).map(\.absoluteString)
    }

    @Test func blueskyThumbnailsBecomeFullSize() {
        let path = "plain/did:plc:z72i7hdynmk6r22z27h6tvur/bafkreih3mb3cwnbc5kv5b2qyy24q6banms25i5ut3cbty4ej2x7vjvd6y4@jpeg"
        #expect(fullSize("https://cdn.bsky.app/img/feed_thumbnail/\(path)") == ["https://cdn.bsky.app/img/feed_fullsize/\(path)"])
        #expect(fullSize("https://cdn.bsky.app/img/avatar_thumbnail/\(path)") == ["https://cdn.bsky.app/img/avatar/\(path)"])
        #expect(fullSize("https://cdn.bsky.app/img/feed_fullsize/\(path)").isEmpty)
    }

    @Test func redditPreviewsPointAtTheOriginal() {
        #expect(fullSize("https://preview.redd.it/q8z5t2v7n4ma1.jpeg?width=640&crop=smart&auto=webp&s=abc")
            == ["https://i.redd.it/q8z5t2v7n4ma1.jpeg"])
        #expect(fullSize("https://preview.redd.it/my-cat-at-the-beach-v0-q8z5t2v7n4ma1.jpeg?width=1080&s=abc")
            == ["https://i.redd.it/q8z5t2v7n4ma1.jpeg"])
        #expect(fullSize("https://external-preview.redd.it/zXc9VbN1.jpeg?width=320&s=abc").isEmpty)
    }

    @Test func imgurThumbnailSuffixIsDropped() {
        #expect(fullSize("https://i.imgur.com/AbCdEfGm.jpg") == ["https://i.imgur.com/AbCdEfG.jpg"])
        #expect(fullSize("https://i.imgur.com/AbCdEh.png") == ["https://i.imgur.com/AbCdE.png"])
        #expect(fullSize("https://i.imgur.com/AbCdEfG.jpg").isEmpty)
        #expect(fromLink("https://imgur.com/AbCdEfG") == ["https://i.imgur.com/AbCdEfG.jpg"])
        #expect(fromLink("https://imgur.com/gallery/AbCdEfG").isEmpty)
    }

    @Test func wikimediaThumbnailsBecome1280pxRenderings() {
        #expect(fullSize("https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/Fronalpstock_big.jpg/330px-Fronalpstock_big.jpg")
            == ["https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/Fronalpstock_big.jpg/1280px-Fronalpstock_big.jpg"])
        #expect(fullSize("https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/Fronalpstock_big.jpg/1280px-Fronalpstock_big.jpg").isEmpty)
        #expect(fullSize("https://upload.wikimedia.org/wikipedia/en/thumb/8/80/Wikipedia-logo-v2.svg/220px-Wikipedia-logo-v2.svg.png")
            == ["https://upload.wikimedia.org/wikipedia/en/thumb/8/80/Wikipedia-logo-v2.svg/1280px-Wikipedia-logo-v2.svg.png"])
        #expect(fullSize("https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Scan.pdf/page1-220px-Scan.pdf.jpg")
            == ["https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Scan.pdf/page1-1280px-Scan.pdf.jpg"])
        #expect(fullSize("https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg").isEmpty)
    }

    @Test func youtubeThumbnailsPreferMaxRes() {
        let expected = ["https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg", "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"]
        #expect(fullSize("https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg?sqp=-oaymwEc&rs=AOn4CLC") == expected)
        #expect(fullSize("https://i.ytimg.com/vi_webp/dQw4w9WgXcQ/mqdefault.webp") == expected)
        #expect(fromLink("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42") == expected)
        #expect(fromLink("https://youtu.be/dQw4w9WgXcQ") == expected)
        #expect(fromLink("https://www.youtube.com/shorts/dQw4w9WgXcQ") == expected)
        #expect(fromLink("https://www.youtube.com/@somechannel").isEmpty)
    }

    @Test func letterboxdPostersGetTheLargeRendering() {
        let base = "https://a.ltrbxd.com/resized/film-poster/8/7/7/3/5/7/877357-all-eyes"
        #expect(fullSize("\(base)-0-460-0-690-crop.jpg?v=b5a5") == ["\(base)-0-1000-0-1500-crop.jpg?v=b5a5"])
        #expect(fullSize("\(base)-0-1000-0-1500-crop.jpg").isEmpty)
        #expect(fullSize("https://a.ltrbxd.com/resized/sm/upload/backdrop-0-1200-0-675-crop.jpg").isEmpty)
    }

    @Test func directImageLinksAreCandidates() {
        #expect(fromLink("https://example.com/photos/cat.JPG") == ["https://example.com/photos/cat.JPG"])
        #expect(fromLink("https://i.redd.it/q8z5t2v7n4ma1.jpeg") == ["https://i.redd.it/q8z5t2v7n4ma1.jpeg"])
        #expect(fromLink("https://example.com/articles/cats").isEmpty)
    }
}

struct ImageResolverTests {
    private func info(link: String? = nil, image: String? = nil) -> HoverInfo {
        var info = HoverInfo(pid: 1)
        info.linkURL = link.flatMap(URL.init(string:))
        info.imageURL = image.flatMap(URL.init(string:))
        return info
    }

    @Test func linkTargetOutranksThumbnailAndOriginalComesLast() {
        let candidates = ImageResolver.candidates(for: info(
            link: "https://i.redd.it/q8z5t2v7n4ma1.jpeg",
            image: "https://preview.redd.it/q8z5t2v7n4ma1.jpeg?width=640&s=abc"
        ))
        #expect(candidates.map(\.absoluteString) == [
            "https://i.redd.it/q8z5t2v7n4ma1.jpeg",
            "https://preview.redd.it/q8z5t2v7n4ma1.jpeg?width=640&s=abc",
        ])
    }

    @Test func plainImageIsItsOwnCandidate() {
        let candidates = ImageResolver.candidates(for: info(image: "https://example.com/a.png"))
        #expect(candidates.map(\.absoluteString) == ["https://example.com/a.png"])
    }

    @Test func nothingToPreview() {
        #expect(ImageResolver.candidates(for: info(link: "https://example.com/about")).isEmpty)
        #expect(ImageResolver.candidates(for: info(image: "blob:https://example.com/1234")).isEmpty)
        #expect(ImageResolver.candidates(for: info()).isEmpty)
    }
}

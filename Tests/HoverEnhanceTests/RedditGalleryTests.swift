import Foundation
import Testing
@testable import HoverEnhance

struct RedditGalleryTests {
    @Test func galleryLinksResolveToTheirID() {
        #expect(RedditGallery.id(fromLink: URL(string: "https://www.reddit.com/gallery/1q2w3er")!) == "1q2w3er")
        #expect(RedditGallery.id(fromLink: URL(string: "https://old.reddit.com/gallery/1q2w3er/")!) == "1q2w3er")
        #expect(RedditGallery.id(fromLink: URL(string: "https://www.reddit.com/r/pics/comments/1q2w3er/mountain_lake/")!) == nil)
        #expect(RedditGallery.id(fromLink: URL(string: "https://example.com/gallery/1q2w3er")!) == nil)
    }

    /// Mirrors the carousel markup on www.reddit.com/gallery/<id>: per item, a preview (eager for
    /// the first, lazy after), a second preview, then the full-size image.
    @Test func carouselYieldsOneFullSizeImagePerItemInOrder() {
        let page = """
        <img src="https://preview.redd.it/unrelated-v0-header1.png?width=64&amp;s=1">
        <gallery-carousel post-id="t3_1q2w3er" advance-animation>
          <li><img src="https://preview.redd.it/mountain-lake-v0-k3v9d2mzp8qa1.jpg?width=640&amp;crop=smart&amp;s=a" srcset="https://preview.redd.it/mountain-lake-v0-k3v9d2mzp8qa1.jpg?width=320&amp;s=b 320w">
              <img src="https://preview.redd.it/mountain-lake-v0-k3v9d2mzp8qa1.jpg?width=1080&amp;s=c">
              <img src="https://i.redd.it/k3v9d2mzp8qa1.jpg"></li>
          <li><img data-lazy-src="https://preview.redd.it/mountain-lake-v0-r7hx5n2wq4tb1.jpg?width=640&amp;s=d" data-lazy-srcset="x 1w">
              <img src="https://i.redd.it/r7hx5n2wq4tb1.jpg"></li>
          <li><img data-lazy-src="https://preview.redd.it/mountain-lake-v0-w2pc8y6fj3sd1.jpg?width=640&amp;s=e"></li>
        </gallery-carousel>
        <img src="https://i.redd.it/somethingelse.jpg">
        """
        #expect(RedditGallery.imageURLs(inPage: page).map(\.absoluteString) == [
            "https://i.redd.it/k3v9d2mzp8qa1.jpg",
            "https://i.redd.it/r7hx5n2wq4tb1.jpg",
            // No full-size copy in the page; the Reddit rule upgrades it later.
            "https://preview.redd.it/mountain-lake-v0-w2pc8y6fj3sd1.jpg?width=640&s=e",
        ])
    }

    @Test func pageWithoutCarouselHasNoImages() {
        #expect(RedditGallery.imageURLs(inPage: "<html><img src=\"https://i.redd.it/a.jpg\"></html>").isEmpty)
    }
}

struct MediaResolverTests {
    @Test func galleryLinkOutranksTheThumbnailInsideIt() {
        var info = HoverInfo(pid: 1)
        info.linkURL = URL(string: "https://www.reddit.com/gallery/1q2w3er")
        info.imageURL = URL(string: "https://b.thumbs.redditmedia.com/abc.jpg")
        #expect(MediaResolver.source(for: info) == .redditGallery(id: "1q2w3er"))
    }

    @Test func aFramesWebsiteIsTheTabsPage() {
        var info = HoverInfo(pid: 1)
        info.pageURL = URL(string: "https://ads.example.net/frame")
        #expect(info.websiteURL == info.pageURL)
        info.topPageURL = URL(string: "https://bank.example/account")
        #expect(info.websiteURL == info.topPageURL)
    }

    @Test func plainTextGetsNoSecondLook() {
        var info = HoverInfo(pid: 1)
        info.role = "AXStaticText"
        #expect(info.isPlainText)
        info.linkURL = URL(string: "https://example.com/")
        #expect(!info.isPlainText)
    }

    @Test func plainImagesStillResolve() {
        var info = HoverInfo(pid: 1)
        info.imageURL = URL(string: "https://example.com/a.png")
        #expect(MediaResolver.source(for: info) == .images([URL(string: "https://example.com/a.png")!]))
        #expect(MediaResolver.source(for: HoverInfo(pid: 1)) == nil)
    }
}

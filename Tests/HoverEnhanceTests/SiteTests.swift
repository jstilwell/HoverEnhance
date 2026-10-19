import Foundation
import os
import Testing
@testable import HoverEnhance

struct SiteLinksTests {
    private func source(_ string: String) -> MediaSource? {
        SiteLinks.source(forLink: URL(string: string)!)
    }

    @Test func videoHosts() {
        #expect(source("https://streamable.com/moo") == .streamable(id: "moo"))
        #expect(source("https://streamable.com/e/moo") == .streamable(id: "moo"))
        #expect(source("https://v.redd.it/a1b2c3d4e5f61") == .video(URL(string: "https://v.redd.it/a1b2c3d4e5f61/HLSPlaylist.m3u8")!))
        #expect(source("https://i.imgur.com/AbCdEfG.gifv") == .video(URL(string: "https://i.imgur.com/AbCdEfG.mp4")!))
        #expect(source("https://example.com/clips/goal.MP4") == .video(URL(string: "https://example.com/clips/goal.MP4")!))
    }

    @Test func postLinks() {
        #expect(source("https://x.com/Passengers/status/821025484150423557") == .tweet(id: "821025484150423557"))
        #expect(source("https://twitter.com/i/status/821025484150423557/video/1") == .tweet(id: "821025484150423557"))
        #expect(source("https://bsky.app/profile/bsky.app/post/3mk4lzkrnk22d") == .blueskyPost(actor: "bsky.app", rkey: "3mk4lzkrnk22d"))
        #expect(source("https://www.reddit.com/gallery/1q2w3er") == .redditGallery(id: "1q2w3er"))
    }

    @Test func redgifsLinks() {
        #expect(source("https://www.redgifs.com/watch/carefulinfantiledromaeosaur") == .redgifs(id: "carefulinfantiledromaeosaur"))
        #expect(source("https://v3.redgifs.com/watch/carefulinfantiledromaeosaur#rel=user") == .redgifs(id: "carefulinfantiledromaeosaur"))
        #expect(source("https://redgifs.com/ifr/carefulinfantiledromaeosaur") == .redgifs(id: "carefulinfantiledromaeosaur"))
        #expect(source("https://i.redgifs.com/i/CarefulInfantileDromaeosaur.jpg") == .redgifs(id: "carefulinfantiledromaeosaur"))
        // Its media files are plain videos.
        #expect(source("https://media.redgifs.com/CarefulInfantileDromaeosaur.mp4")
            == .video(URL(string: "https://media.redgifs.com/CarefulInfantileDromaeosaur.mp4")!))
    }

    @Test func otherLinksAreNotSources() {
        #expect(source("https://streamable.com/") == nil)
        #expect(source("https://x.com/Passengers") == nil)
        // Ids longer than 64 bits overflowed the token X's lookup needs, crashing the app.
        #expect(source("https://x.com/a/status/\(String(repeating: "9", count: 34))") == nil)
        #expect(source("https://x.com/a/status/١٢٣") == nil)
        #expect(source("https://bsky.app/profile/bsky.app") == nil)
        #expect(source("https://i.imgur.com/AbCdEfG.jpg") == nil)
        #expect(source("https://www.redgifs.com/watch/") == nil)
        #expect(source("https://www.redgifs.com/users/someone") == nil)
        #expect(source("https://www.redgifs.com/watch/a.b") == nil)
        #expect(source("https://example.com/article") == nil)
    }
}

/// A video the page already shows under the cursor, as in Instagram's feed.
struct VideoOnThePageTests {
    private func info(link: String? = nil, image: String? = nil, video: CGSize?) -> HoverInfo {
        var info = HoverInfo(pid: 1, appKind: .browser)
        info.pageURL = URL(string: "https://www.instagram.com/")
        info.linkURL = link.flatMap(URL.init(string:))
        info.imageURL = image.flatMap(URL.init(string:))
        info.videoFrame = video.map { CGRect(origin: .zero, size: $0) }
        return info
    }

    @Test func getsNoPreviewOfItself() {
        #expect(MediaResolver.source(for: info(link: "https://www.instagram.com/reel/AbC123/", video: CGSize(width: 470, height: 585))) == nil)
    }

    @Test func getsNoPreviewOfAStillOfItself() {
        #expect(MediaResolver.source(for: info(image: "https://example.com/poster.jpg", video: CGSize(width: 470, height: 585))) == nil)
    }

    @Test func smallLoopingThumbnailsStillPreview() {
        #expect(MediaResolver.source(for: info(link: "https://www.instagram.com/reel/AbC123/", video: CGSize(width: 80, height: 80))) == .instagram(code: "AbC123"))
    }

    @Test func withoutAVideoNothingChanges() {
        #expect(MediaResolver.source(for: info(link: "https://www.instagram.com/reel/AbC123/", video: nil)) == .instagram(code: "AbC123"))
        #expect(MediaResolver.source(for: info(image: "https://example.com/photo.jpg", video: nil)) == .images([URL(string: "https://example.com/photo.jpg")!]))
    }
}

/// A photo outside any link, as in Instagram's feed, where only the time in the post's header links to it.
struct FeedPhotoTests {
    private let photo = URL(string: "https://scontent-xyz1-1.cdninstagram.com/v/t51.2885-15/111111111_2222222222222222_3333333333333333333_n.jpg?stp=dst-jpg_e35_p640x640")!

    private func info(link: String? = nil, post: String?, video: Bool = false) -> HoverInfo {
        var info = HoverInfo(pid: 1, appKind: .browser)
        info.pageURL = URL(string: "https://www.instagram.com/")
        info.linkURL = link.flatMap(URL.init(string:))
        info.imageURL = photo
        info.postURL = post.flatMap(URL.init(string:))
        info.videoFrame = video ? CGRect(x: 0, y: 0, width: 470, height: 585) : nil
        return info
    }

    @Test func comesFromItsPost() {
        #expect(MediaResolver.source(for: info(post: "https://www.instagram.com/p/AbC123/")) == .instagram(code: "AbC123"))
    }

    @Test func aLinkAroundThePhotoStillWins() {
        #expect(MediaResolver.source(for: info(link: "https://www.instagram.com/p/XyZ789/", post: "https://www.instagram.com/p/AbC123/"))
            == .instagram(code: "XyZ789"))
    }

    @Test func withoutAPostItsTheImage() {
        #expect(MediaResolver.source(for: info(post: nil)) == .images([photo]))
    }

    @Test func aVideoPlayingThereStillGetsNoPreview() {
        #expect(MediaResolver.source(for: info(post: "https://www.instagram.com/p/AbC123/", video: true)) == nil)
    }

    @Test func postsCanHoldMore() {
        #expect(MediaSource.instagram(code: "AbC123").isPost)
        #expect(MediaSource.tweet(id: "1").isPost)
        #expect(!MediaSource.images([photo]).isPost)
    }

    @Test func albumsOpenAtThePhotoThePageShows() {
        // The post's lookup gives each photo at another size and server, under the same name.
        let album = Media(items: [
            .image([URL(string: "https://scontent-abc2-2.cdninstagram.com/v/t51.2885-15/444444444_5555555555555555_6666666666666666666_n.jpg?stp=dst-jpg_e15")!]),
            .image([URL(string: "https://scontent-abc2-2.cdninstagram.com/v/t51.2885-15/111111111_2222222222222222_3333333333333333333_n.jpg?stp=dst-jpg_e15")!]),
        ])
        #expect(album.index(showing: photo) == 1)
        // X serves its thumbnails without the extension its full images have.
        let tweet = Media(items: [.image([URL(string: "https://pbs.twimg.com/media/AbCdEfGhIj1.jpg")!]), .image([URL(string: "https://pbs.twimg.com/media/KlMnOpQrSt2.jpg")!])])
        #expect(tweet.index(showing: URL(string: "https://pbs.twimg.com/media/KlMnOpQrSt2?format=jpg&name=small")!) == 1)
        // Names like "media" say nothing about which photo it is.
        #expect(Media(items: [.image([URL(string: "https://www.instagram.com/p/AbC123/media/?size=l")!])])
            .index(showing: URL(string: "https://example.com/media")!) == nil)
    }
}

/// Fixtures are trimmed copies of real responses.
struct SiteAPIsTests {
    @Test func theTweetTokenSurvivesAnyId() {
        #expect(!SiteAPIs.syndicationToken("821025484150423557").isEmpty)
        #expect(SiteAPIs.syndicationToken(String(repeating: "9", count: 400)) == "0")
        #expect(SiteAPIs.syndicationToken("-5") == "0")
    }

    @Test func streamablePrefersTheFullQualityMP4() {
        let json = """
        {"status": 2, "files": {
          "original": {"url": null, "width": 1097, "height": 1920},
          "mp4": {"url": "https://cdn-cf-east.streamable.com/video/mp4/moo.mp4?Expires=1", "width": 718, "height": 410},
          "mp4-mobile": {"url": "https://cdn-cf-east.streamable.com/video/mp4-mobile/moo.mp4?Expires=1", "width": 361, "height": 206}}}
        """
        #expect(SiteAPIs.streamable(Data(json.utf8))?.items == [
            .video(URL(string: "https://cdn-cf-east.streamable.com/video/mp4/moo.mp4?Expires=1")!, size: CGSize(width: 718, height: 410)),
        ])
    }

    @Test func redgifsVideosAndImages() {
        let video = """
        {"gif": {"id": "carefulinfantiledromaeosaur", "type": 1, "width": 540, "height": 960, "gallery": null, "urls": {
          "poster": "https://media.redgifs.com/CarefulInfantileDromaeosaur-poster.jpg",
          "hd": "https://media.redgifs.com/CarefulInfantileDromaeosaur.mp4",
          "sd": "https://media.redgifs.com/CarefulInfantileDromaeosaur-mobile.mp4"}}}
        """
        let gif = SiteAPIs.redgifsGif(Data(video.utf8))
        #expect(gif?.media.items == [
            .video(URL(string: "https://media.redgifs.com/CarefulInfantileDromaeosaur.mp4")!, size: CGSize(width: 540, height: 960)),
        ])
        #expect(gif?.gallery == nil)

        let image = """
        {"gif": {"id": "stiffperfecteuropeanfiresalamander", "type": 2, "width": 1536, "height": 2688,
          "gallery": "1a081774aaa-0601-8b84-0000-9a730627ddb5", "urls": {
          "hd": "https://media.redgifs.com/StiffPerfectEuropeanfiresalamander-large.jpg",
          "sd": "https://media.redgifs.com/StiffPerfectEuropeanfiresalamander-mobile.jpg"}}}
        """
        let still = SiteAPIs.redgifsGif(Data(image.utf8))
        #expect(still?.media.items == [.image([
            URL(string: "https://media.redgifs.com/StiffPerfectEuropeanfiresalamander-large.jpg")!,
            URL(string: "https://media.redgifs.com/StiffPerfectEuropeanfiresalamander-mobile.jpg")!,
        ])])
        #expect(still?.gallery.flatMap(SiteAPIs.redgifsGalleryURL)
            == URL(string: "https://api.redgifs.com/v2/gallery/1a081774aaa-0601-8b84-0000-9a730627ddb5"))
        #expect(SiteAPIs.redgifsGalleryURL(id: "../gifs/x") == nil)
        #expect(SiteAPIs.redgifsGif(Data(#"{"error": {"code": "NotFound"}}"#.utf8)) == nil)
    }

    @Test func redgifsGalleriesBecomeAnAlbum() {
        let json = """
        {"id": "1a08", "gifs": [
          {"type": 2, "urls": {"hd": "https://media.redgifs.com/A-large.jpg"}},
          {"type": 1, "width": 720, "height": 1280, "urls": {"hd": "https://media.redgifs.com/B.mp4"}},
          {"type": 2, "urls": {}}]}
        """
        #expect(SiteAPIs.redgifsGallery(Data(json.utf8))?.items == [
            .image([URL(string: "https://media.redgifs.com/A-large.jpg")!]),
            .video(URL(string: "https://media.redgifs.com/B.mp4")!, size: CGSize(width: 720, height: 1280)),
        ])
    }

    @Test func tweetVideoUsesTheHighestBitrateMP4() {
        let json = """
        {"text": "Plan your escape", "mediaDetails": [{"type": "video",
          "media_url_https": "https://pbs.twimg.com/amplify_video_thumb/820082508054179840/img/a.jpg",
          "original_info": {"width": 617, "height": 616},
          "video_info": {"aspect_ratio": [1, 1], "variants": [
            {"content_type": "application/x-mpegURL", "url": "https://video.twimg.com/amplify_video/820082508054179840/pl/a.m3u8"},
            {"content_type": "video/mp4", "bitrate": 320000, "url": "https://video.twimg.com/amplify_video/820082508054179840/vid/240x240/b.mp4"},
            {"content_type": "video/mp4", "bitrate": 1280000, "url": "https://video.twimg.com/amplify_video/820082508054179840/vid/720x720/c.mp4"},
            {"content_type": "video/mp4", "bitrate": 832000, "url": "https://video.twimg.com/amplify_video/820082508054179840/vid/480x480/d.mp4"}]}}]}
        """
        #expect(SiteAPIs.tweet(Data(json.utf8))?.items == [
            .video(URL(string: "https://video.twimg.com/amplify_video/820082508054179840/vid/720x720/c.mp4")!, size: CGSize(width: 617, height: 616)),
        ])
    }

    @Test func tweetPhotosBecomeAnAlbum() {
        let json = """
        {"mediaDetails": [
          {"type": "photo", "media_url_https": "https://pbs.twimg.com/media/A1.jpg"},
          {"type": "photo", "media_url_https": "https://pbs.twimg.com/media/B2.jpg"}]}
        """
        #expect(SiteAPIs.tweet(Data(json.utf8))?.items == [
            .image([URL(string: "https://pbs.twimg.com/media/A1.jpg?name=orig")!, URL(string: "https://pbs.twimg.com/media/A1.jpg")!]),
            .image([URL(string: "https://pbs.twimg.com/media/B2.jpg?name=orig")!, URL(string: "https://pbs.twimg.com/media/B2.jpg")!]),
        ])
        #expect(SiteAPIs.tweet(Data(#"{"text": "just setting up my twttr"}"#.utf8)) == nil)
    }

    @Test func blueskyVideoAndImages() {
        let video = """
        {"posts": [{"embed": {"$type": "app.bsky.embed.video#view",
          "playlist": "https://video.bsky.app/watch/did%3Aplc%3Az72/bafk/playlist.m3u8", "aspectRatio": {"width": 381, "height": 800}}}]}
        """
        #expect(SiteAPIs.blueskyPost(Data(video.utf8))?.items == [
            .video(URL(string: "https://video.bsky.app/watch/did%3Aplc%3Az72/bafk/playlist.m3u8")!, size: CGSize(width: 381, height: 800)),
        ])
        let images = """
        {"posts": [{"embed": {"$type": "app.bsky.embed.recordWithMedia#view", "record": {},
          "media": {"$type": "app.bsky.embed.images#view", "images": [
            {"fullsize": "https://cdn.bsky.app/img/feed_fullsize/plain/did/a@jpeg", "thumb": "https://cdn.bsky.app/img/feed_thumbnail/plain/did/a@jpeg"},
            {"fullsize": "https://cdn.bsky.app/img/feed_fullsize/plain/did/b@jpeg"}]}}}]}
        """
        #expect(SiteAPIs.blueskyPost(Data(images.utf8))?.items.count == 2)
        #expect(SiteAPIs.blueskyDID(Data(#"{"did": "did:plc:z72i7hdynmk6r22z27h6tvur"}"#.utf8)) == "did:plc:z72i7hdynmk6r22z27h6tvur")
    }
}

/// Answers every request with `status` and an empty JSON object, counting requests by path. Hosts under
/// "nothing" answer 200; others 503.
final class StubAPIServer: URLProtocol, @unchecked Sendable {
    private static let counts = OSAllocatedUnfairLock<[String: Int]>(initialState: [:])
    static func requests(for path: String) -> Int { counts.withLock { $0[path] ?? 0 } }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubAPIServer.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        Self.counts.withLock { $0[url.path(), default: 0] += 1 }
        let status = url.path().contains("nothing") ? 200 : 503
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct MediaFetcherTests {
    @Test func aFailedLookupIsntRepeatedRightAway() async {
        let fetcher = MediaFetcher(configuration: StubAPIServer.configuration())
        let id = "gone\(UUID().uuidString.prefix(8))"
        #expect(await fetcher.lookUp(.streamable(id: id)) == .failed)
        #expect(await fetcher.lookUp(.streamable(id: id)) == .failed)
        #expect(StubAPIServer.requests(for: "/videos/\(id)") == 1)
    }

    @Test func aSiteThatAnswersWithNothingIsntAFailure() async {
        // As for a post without photos or video: no "Couldn't load" for that.
        let fetcher = MediaFetcher(configuration: StubAPIServer.configuration())
        #expect(await fetcher.lookUp(.streamable(id: "nothing\(UUID().uuidString.prefix(8))")) == .nothing)
    }
}

/// RedGIFs' API, where only the second token issued works, as when the first was for another address.
final class RedgifsStub: URLProtocol, @unchecked Sendable {
    private static let tokens = OSAllocatedUnfairLock(initialState: 0)
    static var tokensIssued: Int { tokens.withLock { $0 } }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedgifsStub.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, body): (Int, String)
        if url.path() == "/v2/auth/temporary" {
            let issued = Self.tokens.withLock { $0 += 1; return $0 }
            (status, body) = (200, #"{"token": "t\#(issued)"}"#)
        } else if request.value(forHTTPHeaderField: "Authorization") == "Bearer t2" {
            (status, body) = (200, #"{"gif": {"type": 1, "urls": {"hd": "https://media.redgifs.com/A.mp4"}}}"#)
        } else {
            (status, body) = (401, "{}")
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct RedgifsFetcherTests {
    @Test func aTokenThatStopsWorkingIsReplacedOnce() async {
        let fetcher = MediaFetcher(configuration: RedgifsStub.configuration())
        #expect(await fetcher.lookUp(.redgifs(id: "a")) == .found(Media(items: [.video(URL(string: "https://media.redgifs.com/A.mp4")!, size: nil)])))
        #expect(RedgifsStub.tokensIssued == 2)
        // A token that works is kept.
        #expect(await fetcher.lookUp(.redgifs(id: "b")) != .failed)
        #expect(RedgifsStub.tokensIssued == 2)
    }
}

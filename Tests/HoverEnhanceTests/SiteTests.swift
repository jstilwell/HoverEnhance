import Foundation
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

    @Test func otherLinksAreNotSources() {
        #expect(source("https://streamable.com/") == nil)
        #expect(source("https://x.com/Passengers") == nil)
        #expect(source("https://bsky.app/profile/bsky.app") == nil)
        #expect(source("https://i.imgur.com/AbCdEfG.jpg") == nil)
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

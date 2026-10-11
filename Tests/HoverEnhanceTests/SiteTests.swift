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

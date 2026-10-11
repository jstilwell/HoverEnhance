import Foundation
import Testing
@testable import HoverEnhance

struct InstagramTests {
    @Test func postLinks() {
        let source = { (string: String) in SiteLinks.source(forLink: URL(string: string)!) }
        #expect(source("https://www.instagram.com/p/Cq4ZbRtXy2k/?exln=ZXhhbXBsZQ==") == .instagram(code: "Cq4ZbRtXy2k"))
        #expect(source("https://www.instagram.com/reel/Cx7LmNpQrSt/") == .instagram(code: "Cx7LmNpQrSt"))
        #expect(source("https://www.instagram.com/exampleaccount/p/Cq4ZbRtXy2k/") == .instagram(code: "Cq4ZbRtXy2k"))
        #expect(source("https://www.instagram.com/exampleaccount/") == nil)
        // A post's song.
        #expect(source("https://www.instagram.com/reels/audio/1234567890123456/") == nil)
    }

    /// Builds an embed page the way Instagram does: the post as JSON, inside a JSON string, inside
    /// the JSON passed to a script.
    private func embedPage(post: [String: Any]) throws -> String {
        let context = try JSONSerialization.data(withJSONObject: ["context": ["type": "x"], "gql_data": ["shortcode_media": post]])
        let outer = try JSONSerialization.data(withJSONObject: [["contextJSON": String(decoding: context, as: UTF8.self)]])
        return "<script>s.handle({\"require\":[[\"PolarisEmbedSimple\",\"init\",[],\(String(decoding: outer, as: UTF8.self))]]});</script>"
    }

    @Test func reelPlaysItsVideo() throws {
        let page = try embedPage(post: [
            "__typename": "GraphVideo", "is_video": true,
            "display_url": "https://scontent.cdninstagram.com/v/poster.jpg?a=1&b=2",
            "video_url": "https://scontent.cdninstagram.com/o1/v/clip.mp4?x=1&y=2",
            // Quotes and backslashes in captions must survive both layers.
            "edge_media_to_caption": ["edges": [["node": ["text": "She said \"go\" \\ and went"]]]],
        ])
        #expect(SiteAPIs.instagram(embedPage: page)?.items == [.video(URL(string: "https://scontent.cdninstagram.com/o1/v/clip.mp4?x=1&y=2")!, size: nil)])
    }

    @Test func multiPhotoPostIsAnAlbum() throws {
        let page = try embedPage(post: [
            "__typename": "GraphSidecar", "is_video": false, "display_url": "https://cdn/a.jpg",
            "edge_sidecar_to_children": ["edges": [
                ["node": ["__typename": "GraphImage", "is_video": false, "display_url": "https://cdn/a.jpg"]],
                ["node": ["__typename": "GraphVideo", "is_video": true, "display_url": "https://cdn/b.jpg", "video_url": "https://cdn/b.mp4"]],
                ["node": ["__typename": "GraphImage", "is_video": false, "display_url": "https://cdn/c.jpg"]],
            ]],
        ])
        #expect(SiteAPIs.instagram(embedPage: page)?.items == [
            .image([URL(string: "https://cdn/a.jpg")!]),
            .video(URL(string: "https://cdn/b.mp4")!, size: nil),
            .image([URL(string: "https://cdn/c.jpg")!]),
        ])
    }

    @Test func pageWithEmbeddingOffHasNoMedia() {
        let page = #"<div class="EmbedBroken">The link to this photo or video may be broken, or the post may have been removed.</div>"#
        #expect(SiteAPIs.instagram(embedPage: page) == nil)
    }

    @Test func fallbackImageURL() {
        #expect(SiteAPIs.instagramImageURL(code: "Cq4ZbRtXy2k").absoluteString == "https://www.instagram.com/p/Cq4ZbRtXy2k/media/?size=l")
    }
}

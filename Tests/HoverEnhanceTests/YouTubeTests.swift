import Foundation
import Testing
@testable import HoverEnhance

struct YouTubeLinkTests {
    private func ref(_ string: String) -> YouTubeChannelRef? { YouTube.channelRef(fromLink: URL(string: string)!) }

    @Test func linksLeadToChannels() {
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RD&start_radio=1") == .video("dQw4w9WgXcQ"))
        #expect(ref("https://youtu.be/dQw4w9WgXcQ") == .video("dQw4w9WgXcQ"))
        #expect(ref("https://www.youtube.com/shorts/dQw4w9WgXcQ") == .video("dQw4w9WgXcQ"))
        #expect(ref("https://www.youtube.com/@RickAstleyYT/videos") == .handle("RickAstleyYT"))
        #expect(ref("https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw") == .id("UCuAXFkgsw1L7xaCfnd5JJOw"))
        #expect(ref("https://www.youtube.com/c/SomeName") == .legacyPath("/c/SomeName"))
        #expect(ref("https://www.youtube.com/feed/subscriptions") == nil)
        #expect(ref("https://vimeo.com/76979871") == nil)
    }
}

struct YouTubePageTests {
    /// Encodes JSON the way YouTube's channel pages do: a single-quoted JavaScript string with
    /// punctuation as \x escapes.
    private func page(with object: [String: Any]) throws -> String {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        var literal = ""
        for scalar in json.unicodeScalars {
            if "{}\":[],'\\".unicodeScalars.contains(scalar) {
                literal += String(format: "\\x%02x", scalar.value)
            } else {
                literal.unicodeScalars.append(scalar)
            }
        }
        return "<script>var ytInitialData = '\(literal)';</script><script>window['ytInitialData'] = JSON.parse(window['ytInitialData']);</script>"
    }

    @Test func javaScriptStringsDecode() {
        #expect(YouTube.javaScriptString(atStartOf: #"'\x7b\x22a\x22:1\x7dé it\'s ’🎄';rest"#[...]) == "{\"a\":1}é it's ’🎄")
        #expect(YouTube.javaScriptString(atStartOf: "'unterminated"[...]) == nil)
    }

    @Test func channelPageYieldsTheCard() throws {
        let html = try page(with: [
            "metadata": ["channelMetadataRenderer": [
                "title": "Rick Astley",
                "externalId": "UCuAXFkgsw1L7xaCfnd5JJOw",
                "vanityChannelUrl": "http://www.youtube.com/@RickAstleyYT",
                "description": "Rick Astley’s Swinging Christmas 🎄 \"SOLD OUT\"\n",
                "avatar": ["thumbnails": [["url": "https://yt3.example/small"], ["url": "https://yt3.example/large", "width": 900]]],
            ]],
            "header": ["pageHeaderRenderer": ["content": ["rows": [
                ["parts": [["text": ["content": "@RickAstleyYT"]], ["text": ["content": "4.55M subscribers"]], ["text": ["content": "437 videos"]]]],
            ]]]],
        ])
        let channel = try #require(YouTube.channel(inPage: html))
        #expect(channel == YouTubeChannel(
            id: "UCuAXFkgsw1L7xaCfnd5JJOw", title: "Rick Astley", handle: "RickAstleyYT",
            description: "Rick Astley’s Swinging Christmas 🎄 \"SOLD OUT\"",
            avatar: URL(string: "https://yt3.example/large"), subscribers: "4.55M subscribers", videos: "437 videos"
        ))
        #expect(channel.url.absoluteString == "https://www.youtube.com/@RickAstleyYT")
    }

    @Test func plainObjectFormAlsoWorks() {
        let html = #"<script>var ytInitialData = {"metadata":{"channelMetadataRenderer":{"title":"T","externalId":"UC1","description":""}}};</script>"#
        #expect(YouTube.channel(inPage: html)?.title == "T")
    }

    @Test func oEmbedNamesTheChannel() {
        let json = #"{"author_name":"Rick Astley","author_url":"https://www.youtube.com/@RickAstleyYT","title":"Never Gonna Give You Up"}"#
        #expect(YouTube.channelPageURL(fromOEmbed: Data(json.utf8))?.absoluteString == "https://www.youtube.com/@RickAstleyYT")
    }
}

struct YouTubeHoverRuleTests {
    private func info(link: String, onText: Bool, image: String? = nil) -> HoverInfo {
        var info = HoverInfo(pid: 1)
        info.pageURL = URL(string: "https://www.youtube.com/results?search_query=rick")
        info.linkURL = URL(string: link)
        info.imageURL = image.flatMap(URL.init(string:))
        info.isOnText = onText
        return info
    }

    @Test func titleTextGetsACreatorCard() {
        #expect(MediaResolver.source(for: info(link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", onText: true)) == .youtubeChannel(.video("dQw4w9WgXcQ")))
        #expect(MediaResolver.source(for: info(link: "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", onText: true)) == .youtubeChannel(.id("UCuAXFkgsw1L7xaCfnd5JJOw")))
    }

    @Test func mediaOnYouTubeIsLeftAlone() {
        #expect(MediaResolver.source(for: info(link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", onText: false)) == nil)
        #expect(MediaResolver.source(for: info(link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", onText: false,
                                               image: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")) == nil)
    }

    @Test func textLinksToOtherSitesStillPreview() {
        #expect(MediaResolver.source(for: info(link: "https://streamable.com/moo", onText: true)) == .streamable(id: "moo"))
    }

    @Test func cardsCanBeTurnedOff() {
        #expect(!PreviewFilter(cards: false).allows(.youtubeChannel(.video("dQw4w9WgXcQ"))))
        #expect(!PreviewFilter(disabledSites: [.youtube]).allows(.youtubeChannel(.video("dQw4w9WgXcQ"))))
    }
}

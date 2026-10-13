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
                ["accessibility": ["label": "4.55 million subscribers"]],
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

    @Test func channelHeaderGivesTheBannerAndCheck() throws {
        let html = try page(with: [
            "metadata": ["channelMetadataRenderer": ["title": "Lex Clips", "externalId": "UCJIfeSCssxSC_Dhc5s7woww", "description": ""]],
            "header": ["pageHeaderRenderer": ["content": ["pageHeaderViewModel": [
                "title": ["dynamicTextViewModel": ["text": ["content": "Lex Clips", "attachmentRuns": [
                    ["element": ["type": ["imageType": ["image": ["sources": [["clientResource": ["imageName": "CHECK_CIRCLE_FILLED"]]]]]]]],
                ]]]],
                "banner": ["imageBannerViewModel": ["image": ["sources": [
                    ["url": "https://yt3.example/banner=w1707", "width": 1707],
                    ["url": "https://yt3.example/banner=w1060", "width": 1060],
                    ["url": "https://yt3.example/banner=w640", "width": 640],
                ]]]],
            ]]]],
        ])
        let channel = try #require(YouTube.channel(inPage: html))
        #expect(channel.isVerified)
        // The smallest that's sharp on a Retina display.
        #expect(channel.banner?.absoluteString == "https://yt3.example/banner=w1060")
    }

    @Test func channelsWithoutBannerOrCheck() {
        let html = #"<script>var ytInitialData = {"metadata":{"channelMetadataRenderer":{"title":"T","externalId":"UC1","description":""}}};</script>"#
        let channel = YouTube.channel(inPage: html)
        #expect(channel?.banner == nil && channel?.isVerified == false)
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

struct YouTubeWatchPageTests {
    private func page(details: [String: Any], micro: [String: Any]) throws -> String {
        let response: [String: Any] = ["videoDetails": details, "microformat": ["playerMicroformatRenderer": micro]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        // More script follows the object on the same line, as on YouTube's pages.
        return "<script>var ytInitialPlayerResponse = \(json);var meta = document.createElement('meta');</script>"
    }

    private let details: [String: Any] = [
        "videoId": "-qRc7qou6XY", "title": "George Hotz: I'd put money on Mark Zuckerberg", "lengthSeconds": "369",
        "viewCount": "37852", "channelId": "UCJIfeSCssxSC_Dhc5s7woww", "allowRatings": true,
        "shortDescription": "Full episode: https://example.com/{not json}\n",
    ]
    private let micro: [String: Any] = [
        "likeCount": "630", "publishDate": "2023-06-29T23:52:58-07:00", "category": "Science & Technology",
        "thumbnail": ["thumbnails": [["url": "https://i.ytimg.com/vi/-qRc7qou6XY/maxresdefault.jpg", "width": 1280, "height": 720]]],
    ]

    @Test func watchPageYieldsTheVideoAndItsChannel() throws {
        let (video, channelPage) = try #require(YouTube.video(inPage: try page(details: details, micro: micro)))
        #expect(video == YouTubeVideo(
            id: "-qRc7qou6XY", title: "George Hotz: I'd put money on Mark Zuckerberg", length: 369, isLive: false,
            views: 37852, likes: 630, published: Date(timeIntervalSince1970: 1_688_107_978), category: "Science & Technology",
            description: "Full episode: https://example.com/{not json}",
            thumbnail: URL(string: "https://i.ytimg.com/vi/-qRc7qou6XY/maxresdefault.jpg")
        ))
        #expect(channelPage?.absoluteString == "https://www.youtube.com/channel/UCJIfeSCssxSC_Dhc5s7woww")
    }

    @Test func hiddenRatingsAndLiveStreamsLeaveThoseOut() throws {
        var live = details
        live["allowRatings"] = false
        live["isLive"] = true
        live["lengthSeconds"] = "0"
        let (video, _) = try #require(YouTube.video(inPage: try page(details: live, micro: micro)))
        #expect(video.likes == nil && video.length == nil && video.isLive)
    }

    @Test func oddChannelIDsAndLocalImagesAreDropped() throws {
        var odd = details
        odd["channelId"] = "UC/../../elsewhere?x=1"
        var local = micro
        local["thumbnail"] = ["thumbnails": [["url": "http://192.168.1.1/thumb.jpg", "width": 1280]]]
        let (video, channelPage) = try #require(YouTube.video(inPage: try page(details: odd, micro: local)))
        #expect(channelPage == nil && video.thumbnail == nil)
    }

    @Test func objectLiteralsEndAtTheirOwnBrace() {
        #expect(YouTube.objectLiteral(atStartOf: #"{"a":"}\"{","b":{"c":1}};var x = {};"#[...]) == #"{"a":"}\"{","b":{"c":1}}"#)
        #expect(YouTube.objectLiteral(atStartOf: #"{"unterminated":"#[...]) == nil)
    }

    @Test func countsAndAgesReadLikeYouTube() {
        let us = Locale(identifier: "en_US")
        #expect(YouTubeFormat.count(630, locale: us) == "630")
        #expect(YouTubeFormat.count(1_640_000, locale: us) == "1.6M")
        let now = Date(timeIntervalSince1970: 1_791_841_947)
        #expect(YouTubeFormat.age(Date(timeIntervalSince1970: 1_688_107_978), relativeTo: now, locale: us) == "3 years ago")
        #expect(YouTubeFormat.length(369) == "6:09")
    }
}

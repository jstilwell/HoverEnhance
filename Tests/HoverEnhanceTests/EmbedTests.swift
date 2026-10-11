import Foundation
import Testing
@testable import HoverEnhance

struct EmbedTests {
    private func embed(_ string: String) -> Embed? {
        Embed.from(link: URL(string: string)!)
    }

    @Test func youtubeLinks() {
        #expect(embed("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == Embed(site: .youtube, id: "dQw4w9WgXcQ"))
        #expect(embed("https://youtu.be/dQw4w9WgXcQ?t=90") == Embed(site: .youtube, id: "dQw4w9WgXcQ", start: 90))
        #expect(embed("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s") == Embed(site: .youtube, id: "dQw4w9WgXcQ", start: 90))
        #expect(embed("https://www.youtube.com/shorts/dQw4w9WgXcQ") == Embed(site: .youtube, id: "dQw4w9WgXcQ", isPortrait: true))
        #expect(embed("https://www.youtube.com/@somechannel") == nil)
        #expect(embed("https://www.youtube.com/watch?v=short") == nil)
    }

    @Test func otherSites() {
        #expect(embed("https://vimeo.com/76979871") == Embed(site: .vimeo, id: "76979871"))
        #expect(embed("https://vimeo.com/76979871/abc123def") == Embed(site: .vimeo, id: "76979871", hash: "abc123def"))
        // Hashes are checked like ids, so a link can't add its own parameters to the player's address.
        #expect(embed("https://vimeo.com/76979871/abc%26autoplay=0") == Embed(site: .vimeo, id: "76979871"))
        #expect(embed("https://player.vimeo.com/video/76979871?h=abc%22x") == Embed(site: .vimeo, id: "76979871"))
        #expect(embed("https://vimeo.com/channels/staffpicks/76979871") == Embed(site: .vimeo, id: "76979871"))
        #expect(embed("https://www.tiktok.com/@scout2015/video/6718335390845095173") == Embed(site: .tiktok, id: "6718335390845095173", isPortrait: true))
        #expect(embed("https://clips.twitch.tv/FunnyClipSlug-AbC123") == Embed(site: .twitch, id: "FunnyClipSlug-AbC123"))
        #expect(embed("https://www.twitch.tv/somechannel/clip/FunnyClipSlug-AbC123") == Embed(site: .twitch, id: "FunnyClipSlug-AbC123"))
        #expect(embed("https://www.twitch.tv/somechannel") == nil)
    }

    @Test func playerURLsCarryMuteAndStart() {
        let video = Embed(site: .youtube, id: "dQw4w9WgXcQ", start: 90)
        #expect(video.playerURL(muted: true)?.absoluteString
            == "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1&mute=1&playsinline=1&rel=0&start=90")
        let clip = Embed(site: .twitch, id: "Slug")
        #expect(clip.playerURL(muted: false)?.absoluteString.contains("parent=\(Embed.origin.host()!)") == true)
    }

    @Test func linksOnTheSiteItselfAreLeftAlone() {
        var info = HoverInfo(pid: 1)
        info.linkURL = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        info.pageURL = URL(string: "https://www.reddit.com/r/videos/")
        #expect(MediaResolver.source(for: info) == .embed(Embed(site: .youtube, id: "dQw4w9WgXcQ")))
        info.pageURL = URL(string: "https://www.youtube.com/feed/subscriptions")
        #expect(MediaResolver.source(for: info) != .embed(Embed(site: .youtube, id: "dQw4w9WgXcQ")))
    }
}

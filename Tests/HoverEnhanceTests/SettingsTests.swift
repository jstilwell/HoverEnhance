import AppKit
import Foundation
import Testing
@testable import HoverEnhance

@MainActor
struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "HoverEnhanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsMatchTheAppsBehaviorBeforeSettingsExisted() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.previewsEnabled)
        #expect(settings.activation == .always)
        #expect(settings.hoverDelay == 150)
        #expect(settings.minimumEnlargement == 1.2)
        #expect(settings.maximumSize == 1)
        #expect(settings.showsNotch)
        #expect(settings.videosStartMuted)
        #expect(settings.loopVideos && settings.resumeVideos)
        #expect(settings.filter == PreviewFilter())
    }

    @Test func finderDefaultsShowEverything() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.finderCards)
        #expect(settings.finderDelay == 600)
        #expect(settings.fileCard == FileCardOptions())
    }

    @Test func finderChangesPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.finderCards = false
        settings.finderDelay = 900
        settings.finderShowsPath = false
        settings.finderPathStyle = .quoted
        settings.finderShowsDates = false
        settings.finderShowsWhereFrom = false
        settings.finderOffersQuit = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.filter.files)
        #expect(reloaded.finderDelay == 900)
        #expect(reloaded.fileCard == FileCardOptions(path: false, pathStyle: .quoted, dates: false, whereFrom: false, offersQuit: false))
    }

    @Test func changesPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.hoverDelay = 75
        settings.activation = .whileHoldingKey
        settings.activationKey = .command
        settings.disabledSites = [.tiktok, .x]
        settings.excludedApps = [ExcludedApp(bundleID: "com.figma.Desktop", name: "Figma")]
        settings.videoSound = .unmuted

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.hoverDelay == 75)
        #expect(reloaded.activation == .whileHoldingKey)
        #expect(reloaded.activationKey == .command)
        #expect(reloaded.disabledSites == [.tiktok, .x])
        #expect(reloaded.isExcluded("com.figma.Desktop"))
        #expect(!reloaded.isExcluded("com.google.Chrome"))
        #expect(!reloaded.videosStartMuted)
    }

    @Test func activationModes() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.activationKey = .option
        settings.activation = .whileHoldingKey
        #expect(settings.previewsAllowed(holding: [.option]))
        #expect(!settings.previewsAllowed(holding: [.shift]))
        settings.activation = .unlessHoldingKey
        #expect(!settings.previewsAllowed(holding: [.option, .shift]))
        #expect(settings.previewsAllowed(holding: []))
        settings.activation = .always
        #expect(settings.previewsAllowed(holding: [.option]))
    }
}

struct PreviewFilterTests {
    @Test func sourcesKnowTheirSite() {
        #expect(MediaSource.images([URL(string: "https://i.redd.it/a.jpg")!]).site == .reddit)
        #expect(MediaSource.images([URL(string: "https://cdn.bsky.app/img/feed_thumbnail/plain/x@jpeg")!]).site == .bluesky)
        #expect(MediaSource.images([URL(string: "https://example.com/a.jpg")!]).site == nil)
        #expect(MediaSource.video(URL(string: "https://v.redd.it/abc/HLSPlaylist.m3u8")!).site == .reddit)
        #expect(MediaSource.embed(Embed(site: .tiktok, id: "1")).site == .tiktok)
        #expect(MediaSource.tweet(id: "1").site == .x)
    }

    @Test func turnedOffSitesAndKindsAreSkipped() {
        var filter = PreviewFilter()
        filter.disabledSites = [.reddit]
        #expect(!filter.allows(.redditGallery(id: "1q2w3er")))
        #expect(!filter.allows(.images([URL(string: "https://i.redd.it/a.jpg")!])))
        #expect(filter.allows(.images([URL(string: "https://example.com/a.jpg")!])))

        filter = PreviewFilter(videos: false, embeds: false)
        #expect(!filter.allows(.streamable(id: "abc")))
        #expect(!filter.allows(.embed(Embed(site: .youtube, id: "dQw4w9WgXcQ"))))
        #expect(filter.allows(.tweet(id: "1")))
    }

    @Test func applyDropsKindsAndCollapsesAlbums() {
        let media = Media(items: [
            .image([URL(string: "https://cdn/a.jpg")!]),
            .video(URL(string: "https://cdn/b.mp4")!, size: nil),
            .image([URL(string: "https://cdn/c.jpg")!]),
        ])
        #expect(PreviewFilter(videos: false).apply(to: media)?.items.count == 2)
        #expect(PreviewFilter(albums: false).apply(to: media)?.items == [.image([URL(string: "https://cdn/a.jpg")!])])
        #expect(PreviewFilter(images: false, videos: false).apply(to: media) == nil)
    }
}

struct PreviewSizeLimitTests {
    @Test func maximumSizeShrinksThePreview() throws {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let anchor = CGPoint(x: 400, y: 500)
        let full = try #require(PreviewGeometry.panelFrame(anchor: anchor, naturalSize: CGSize(width: 4000, height: 3000), visible: visible))
        let half = try #require(PreviewGeometry.panelFrame(anchor: anchor, naturalSize: CGSize(width: 4000, height: 3000), visible: visible, maxFraction: 0.5))
        #expect(half.height <= visible.height * 0.5)
        #expect(half.height < full.height)
        #expect(half.minX == full.minX)
    }
}

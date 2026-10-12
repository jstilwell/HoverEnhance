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
        #expect(settings.largestImageBytes == 25_000_000)
    }

    @Test func otherAppsStartOffWithTheSafeChoices() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.otherApps == OtherAppsPolicy())
        #expect(!settings.usesActivationKey)

        settings.previewsInOtherApps = true
        settings.otherAppsSkipEmail = false
        settings.otherAppsKnownSitesOnly = false
        settings.otherAppsNeedKey = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.otherApps == OtherAppsPolicy(enabled: true, skipsEmail: false, knownSitesOnly: false, needsKey: true))
        // Holding the key matters now, though previews otherwise always appear.
        #expect(reloaded.activation == .always && reloaded.usesActivationKey)
    }

    @Test func finderDefaultsShowEverything() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.finderCards)
        #expect(settings.finderDelay == 600)
        #expect(settings.fileCard == FileCardOptions())
        #expect(settings.finderOnDesktop && settings.finderForFolders)
        #expect(settings.finderClosesOnKeyPress)
    }

    @Test func finderChangesPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.finderCards = false
        settings.finderDelay = 900
        settings.finderPathStyle = .quoted
        settings.finderHiddenFields = [.path, .opened, .whereFrom]
        settings.finderOffersQuit = false
        settings.finderCopiesDetails = false
        settings.finderOnDesktop = false
        settings.finderForFolders = false
        settings.finderClosesOnKeyPress = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.filter.files)
        #expect(!reloaded.filter.filesOnDesktop && !reloaded.filter.folders)
        #expect(reloaded.finderDelay == 900)
        #expect(!reloaded.finderClosesOnKeyPress)
        #expect(reloaded.fileCard == FileCardOptions(hidden: [.path, .opened, .whereFrom], pathStyle: .quoted, offersQuit: false, copiesDetails: false))
    }

    @Test func unknownHiddenFieldsAreIgnored() {
        let defaults = freshDefaults()
        defaults.set(["opened", "somethingRemoved"], forKey: "finderHiddenFields")
        #expect(AppSettings(defaults: defaults).finderHiddenFields == [.opened])
    }

    @Test func restoringFinderDefaultsMatchesAFreshStart() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.finderCards = false
        settings.finderDelay = 1500
        settings.finderPathStyle = .tilde
        settings.finderHiddenFields = Set(FileCardField.allCases)
        settings.finderOnDesktop = false
        settings.finderCopiesDetails = false
        settings.finderOffersQuit = false
        settings.restoreFinderDefaults()

        let fresh = AppSettings(defaults: freshDefaults())
        #expect(settings.finderCards == fresh.finderCards)
        #expect(settings.finderDelay == fresh.finderDelay)
        #expect(settings.fileCard == fresh.fileCard)
        #expect(settings.filter == fresh.filter)
        #expect(settings.finderClosesOnKeyPress == fresh.finderClosesOnKeyPress)
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

    @Test func skippedWebsitesAndTheShortcutPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.skippedWebsites.isEmpty && settings.pauseShortcut == nil)
        settings.skippedWebsites = ["bank.example"]
        settings.pauseShortcut = Shortcut(keyCode: 35, modifiers: [.command, .option], key: "P")
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.skippedWebsites == ["bank.example"])
        #expect(reloaded.pauseShortcut?.label == "⌥⌘P")
        #expect(reloaded.skips(page: URL(string: "https://login.bank.example/home")))
        #expect(!reloaded.skips(page: URL(string: "https://notbank.example/")))
        reloaded.pauseShortcut = nil
        #expect(AppSettings(defaults: defaults).pauseShortcut == nil)
    }

    @Test func aGreyedOutKeyRequirementDoesntApply() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.previewsInOtherApps = true
        settings.otherAppsNeedKey = true
        #expect(settings.otherApps.needsKey)
        settings.activation = .unlessHoldingKey
        #expect(!settings.otherApps.needsKey)
    }

    @Test func theHoverDelayIsNeverZero() {
        let defaults = freshDefaults()
        defaults.set(0.0, forKey: "hoverDelay")
        #expect(AppSettings(defaults: defaults).hoverDelay == AppSettings.shortestHoverDelay)
    }

    @Test func restingIsLookedAtOnlyWhenAPreviewCouldFollow() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.activationKey = .option
        settings.activation = .whileHoldingKey
        #expect(!settings.inspectsOnRest(holding: []))
        #expect(settings.inspectsOnRest(holding: [.option]))
        settings.previewsEnabled = false
        #expect(!settings.inspectsOnRest(holding: [.option]))
        settings.showsInspector = true
        #expect(settings.inspectsOnRest(holding: []))
    }

    @Test func theInspectorSkipsExcludedAppsAndOtherAppsWhenOff() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.excludedApps = [ExcludedApp(bundleID: "com.google.Chrome", name: "Chrome")]
        #expect(settings.inspectionPolicy == InspectionPolicy(skipped: ["com.google.Chrome"], includesOtherApps: false))
        settings.previewsInOtherApps = true
        #expect(settings.inspectionPolicy.includesOtherApps)
        // The inspector shows everything it finds.
        settings.showsInspector = true
        #expect(settings.inspectionPolicy == InspectionPolicy())
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

struct SettingsTabTests {
    @Test func tabsKeepTheirOrderAndTitles() {
        #expect(SettingsTab.allCases.map(\.title) == ["General", "Previews", "Video", "Sites", "Finder", "Accounts", "Advanced"])
    }
}

struct SkippedWebsitesTests {
    @Test func domainsComeFromWhateverIsTypedOrPasted() {
        #expect(SkippedWebsites.domain(from: "https://www.Bank.example/login?next=1") == "bank.example")
        #expect(SkippedWebsites.domain(from: "  news.example.com  ") == "news.example.com")
        #expect(SkippedWebsites.domain(from: "localhost:3000") == "localhost")
        #expect(SkippedWebsites.domain(from: "not a website") == nil)
        #expect(SkippedWebsites.domain(from: "") == nil)
    }

    @Test func aDomainCoversItsSubdomains() {
        #expect(SkippedWebsites.contains(URL(string: "https://bank.example/"), in: ["bank.example"]))
        #expect(SkippedWebsites.contains(URL(string: "https://www.bank.example/a"), in: ["bank.example"]))
        #expect(!SkippedWebsites.contains(URL(string: "https://bank.example.evil.test/"), in: ["bank.example"]))
        #expect(!SkippedWebsites.contains(nil, in: ["bank.example"]))
    }
}

struct ShortcutTests {
    private func key(_ characters: String, code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    @Test func aShortcutNeedsTwoModifiersOrAFunctionKey() {
        #expect(Shortcut(event: key("p", code: 35, [.control, .option, .command]))?.label == "⌃⌥⌘P")
        #expect(Shortcut(event: key(" ", code: 49, [.option, .command]))?.label == "⌥⌘Space")
        #expect(Shortcut(event: key("", code: 96, [.option]))?.label == "⌥F5")
        #expect(Shortcut(event: key("p", code: 35, [])) == nil)
        #expect(Shortcut(event: key("P", code: 35, [.shift])) == nil)
        // One modifier would take over a key everywhere: ⌘V's pasting, ⌥P's π.
        #expect(Shortcut(event: key("v", code: 9, [.command])) == nil)
        #expect(Shortcut(event: key("p", code: 35, [.option])) == nil)
    }
}

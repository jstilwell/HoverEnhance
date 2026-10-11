import Foundation
import Testing
@testable import HoverEnhance

struct AppKindTests {
    private func info(schemes: [String], htmlTypes: [String] = [], extensions: [String] = []) -> [String: Any] {
        [
            "CFBundleURLTypes": [["CFBundleURLName": "Web", "CFBundleURLSchemes": schemes]],
            "CFBundleDocumentTypes": [["LSItemContentTypes": htmlTypes, "CFBundleTypeExtensions": extensions]],
        ]
    }

    @Test func browsersOpenWebLinksAndHTML() {
        #expect(AppKind(infoDictionary: info(schemes: ["http", "https"], htmlTypes: ["public.html"])) == .browser)
        #expect(AppKind(infoDictionary: info(schemes: ["HTTPS"], extensions: ["htm"])) == .browser)
        // Vivaldi handles email links too, but it's a browser first.
        #expect(AppKind(infoDictionary: info(schemes: ["http", "https", "mailto"], htmlTypes: ["public.html"])) == .browser)
    }

    @Test func takingWebLinksAloneIsntABrowser() {
        // A video downloader takes web links but doesn't open pages; Notes opens HTML but no links.
        #expect(AppKind(infoDictionary: info(schemes: ["http", "https"])) == .other)
        #expect(AppKind(infoDictionary: info(schemes: [], htmlTypes: ["public.html"])) == .other)
        #expect(AppKind(infoDictionary: [:]) == .other)
    }

    @Test func emailAppsHandleMailtoLinks() {
        #expect(AppKind(infoDictionary: info(schemes: ["mailto"])) == .email)
    }

    @Test func installedApps() {
        #expect(AppKind.of(appAt: URL(filePath: "/Applications/Safari.app")) == .browser)
        #expect(AppKind.of(appAt: URL(filePath: "/System/Applications/Mail.app")) == .email)
        #expect(AppKind.of(appAt: URL(filePath: "/System/Applications/Notes.app")) == .other)
    }
}

struct OtherAppsPolicyTests {
    private let image = MediaSource.images([URL(string: "https://tracker.example/pixel.jpg")!])
    private let reddit = MediaSource.redditGallery(id: "abc123")
    private let file = MediaSource.file(URL(filePath: "/tmp/a.txt"), onDesktop: false)

    @Test func browsersAndFileCardsAreAlwaysAllowed() {
        let off = OtherAppsPolicy()
        #expect(off.allows(image, in: .browser, keyHeld: false))
        #expect(off.allows(file, in: .other, keyHeld: false))
    }

    @Test func otherAppsAreOffUnlessTurnedOn() {
        #expect(!OtherAppsPolicy().allows(reddit, in: .other, keyHeld: true))
        #expect(OtherAppsPolicy(enabled: true).allows(reddit, in: .other, keyHeld: false))
    }

    @Test func safetyOptions() {
        let careful = OtherAppsPolicy(enabled: true, skipsEmail: true, knownSitesOnly: true, needsKey: true)
        #expect(!careful.allows(reddit, in: .email, keyHeld: true))
        #expect(!careful.allows(image, in: .other, keyHeld: true))
        #expect(!careful.allows(reddit, in: .other, keyHeld: false))
        #expect(careful.allows(reddit, in: .other, keyHeld: true))

        let open = OtherAppsPolicy(enabled: true, skipsEmail: false, knownSitesOnly: false, needsKey: false)
        #expect(open.allows(image, in: .email, keyHeld: false))
    }
}

struct LocalFileTests {
    private func info(page: String?, link: String? = nil, image: String? = nil) -> HoverInfo {
        var info = HoverInfo(pid: 1, appKind: .browser)
        info.pageURL = page.flatMap(URL.init(string:))
        info.linkURL = link.flatMap(URL.init(string:))
        info.imageURL = image.flatMap(URL.init(string:))
        return info
    }

    @Test func webPagesCantLeadToLocalFiles() {
        #expect(MediaResolver.source(for: info(page: "https://evil.example/", link: "file:///net/evil.example/share/a.jpg")) == nil)
        #expect(MediaResolver.source(for: info(page: "https://evil.example/", image: "file:///Users/me/Pictures/a.png")) == nil)
        #expect(MediaResolver.source(for: info(page: "https://evil.example/", link: "file:///tmp/clip.mp4")) == nil)
        #expect(MediaResolver.source(for: info(page: nil, link: "file:///tmp/a.jpg")) == nil)
    }

    @Test func localPagesCan() {
        let local = info(page: "file:///Users/me/test.html", link: "file:///Users/me/a.jpg")
        #expect(MediaResolver.source(for: local) == .images([URL(string: "file:///Users/me/a.jpg")!]))
    }

    @Test func lookupsKeepOnlyWebAddresses() {
        let answer = Media(items: [
            .image([URL(string: "file:///etc/hosts")!, URL(string: "https://i.redd.it/a.jpg")!]),
            .video(URL(string: "file:///net/host/clip.mp4")!, size: nil),
            .image([URL(string: "file:///tmp/b.png")!]),
        ])
        #expect(answer.webOnly() == Media(items: [.image([URL(string: "https://i.redd.it/a.jpg")!])]))
        #expect(Media(items: [.video(URL(string: "file:///tmp/a.mp4")!, size: nil)]).webOnly() == nil)
    }
}

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

struct LocalNetworkTests {
    @Test func localAddressesAndNames() {
        for host in ["localhost", "app.localhost", "printer.local", "router", "127.0.0.1", "10.0.0.8", "172.20.1.1", "192.168.1.1",
                     "169.254.10.1", "100.100.1.1", "0.0.0.0", "224.0.0.251", "::1", "[::1]", "fe80::1", "fd12:3456::1",
                     "::ffff:192.168.1.1", "printer.local.", "3232235777", "0xC0A80101", "0300.0250.1.1", "10.1"] {
            #expect(LocalNetwork.contains(host: host), "\(host)")
        }
    }

    @Test func publicAddressesAndNames() {
        for host in ["example.com", "i.redd.it", "8.8.8.8", "172.32.0.1", "100.128.0.1", "2606:4700::1111", "::ffff:8.8.8.8", "local.example.com"] {
            #expect(!LocalNetwork.contains(host: host), "\(host)")
        }
        #expect(!LocalNetwork.contains(URL(string: "data:image/png;base64,AAAA")))
        #expect(!LocalNetwork.contains(URL(filePath: "/tmp/a.png")))
    }

    @Test func redirectsMayNotLeaveTheWebForTheLocalNetwork() {
        let web = URL(string: "https://example.com/a.jpg")
        let lan = URL(string: "http://192.168.1.1/a.jpg")
        #expect(!LocalRedirectGuard.allows(from: web, to: lan))
        #expect(LocalRedirectGuard.allows(from: web, to: URL(string: "https://cdn.example.com/a.jpg")))
        #expect(LocalRedirectGuard.allows(from: URL(string: "http://localhost:3000/a.jpg"), to: lan))
    }

    @Test func webPagesCantLeadToTheLocalNetwork() {
        func info(page: String?, link: String? = nil, image: String? = nil) -> HoverInfo {
            var info = HoverInfo(pid: 1, appKind: .browser)
            info.pageURL = page.flatMap(URL.init(string:))
            info.linkURL = link.flatMap(URL.init(string:))
            info.imageURL = image.flatMap(URL.init(string:))
            return info
        }
        #expect(MediaResolver.source(for: info(page: "https://evil.example/", link: "http://192.168.1.1/cgi-bin/x?.jpg")) == nil)
        #expect(MediaResolver.source(for: info(page: "https://evil.example/", image: "http://router.local/a.png")) == nil)
        #expect(MediaResolver.source(for: info(page: nil, link: "http://localhost:8080/clip.mp4")) == nil)
        // A page that's itself local may show its own images.
        let local = URL(string: "http://localhost:3000/a.png")!
        #expect(MediaResolver.source(for: info(page: "http://localhost:3000/", image: local.absoluteString)) == .images([local]))
        // Lookups can't hand back local addresses either.
        #expect(Media(items: [.image([URL(string: "http://10.0.0.1/a.jpg")!])]).webOnly() == nil)
    }
}

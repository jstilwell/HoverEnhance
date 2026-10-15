import CoreGraphics
import Foundation
import Testing
@testable import HoverEnhance

struct NetworkWordsTests {
    @Test func signalStepsFollowApplesThresholds() {
        typealias Quality = NetworkSnapshot.WiFi.Quality
        #expect(Quality(rssi: -44) == .excellent && Quality(rssi: -55) == .excellent)
        #expect(Quality(rssi: -56) == .good && Quality(rssi: -67) == .good)
        #expect(Quality(rssi: -70) == .fair)
        #expect(Quality(rssi: -80) == .weak)
        #expect(Quality.weak.bars == 1 && Quality.fair.bars == 1 && Quality.good.bars == 2 && Quality.excellent.bars == 3)
    }

    @Test func coreWLANValuesBecomeNames() {
        #expect(NetworkSnapshot.WiFi.Standard(rawValue: 6)?.name == "Wi-Fi 6")
        #expect(NetworkSnapshot.WiFi.Standard(rawValue: 7)?.ieee == "802.11be")
        #expect(NetworkSnapshot.WiFi.Standard(rawValue: 0) == nil, "no PHY mode means not joined")
        #expect(NetworkSnapshot.WiFi.Security(coreWLAN: 4)?.name == "WPA2 Personal")
        #expect(NetworkSnapshot.WiFi.Security(coreWLAN: 13)?.name == "WPA2/WPA3 Personal")
        #expect(NetworkSnapshot.WiFi.Security(coreWLAN: 0)?.isWeak == true)
        #expect(NetworkSnapshot.WiFi.Security(coreWLAN: Int.max) == nil, "unknown says nothing")
        #expect(NetworkReader.band(raw: 2) == .ghz5 && NetworkReader.band(raw: 3) == .ghz6 && NetworkReader.band(raw: 0) == nil)
        #expect(NetworkReader.width(raw: 3) == 80 && NetworkReader.width(raw: 0) == nil)
    }

    @Test func speedsReadAsActivityMonitorWritesThem() {
        #expect(NetworkWords.linkSpeed(bitsPerSecond: 1e9) == "1 Gbps")
        #expect(NetworkWords.linkSpeed(bitsPerSecond: 2.5e9) == "2.5 Gbps")
        #expect(NetworkWords.linkSpeed(bitsPerSecond: 358_560_000) == "359 Mbps")
        #expect(NetworkWords.rate(bytesPerSecond: 0) == "0 KB/s")
        #expect(NetworkWords.rate(bytesPerSecond: 340_000) == "340 KB/s")
        #expect(NetworkWords.rate(bytesPerSecond: 12_400_000) == "12 MB/s")
        #expect(NetworkWords.rate(bytesPerSecond: 2_450_000) == "2.5 MB/s")
    }

    @Test func masksBecomePrefixLengths() {
        #expect(NetworkWords.prefixLength(ofMask: "255.255.255.0") == 24)
        #expect(NetworkWords.prefixLength(ofMask: "255.255.252.0") == 22)
        #expect(NetworkWords.prefixLength(ofMask: "255.255.255.255") == 32)
        #expect(NetworkWords.prefixLength(ofMask: "0.0.0.0") == 0)
        #expect(NetworkWords.prefixLength(ofMask: "255.0.255.0") == nil)
        #expect(NetworkWords.prefixLength(ofMask: "nonsense") == nil)
    }

    @Test func tunnelsAreVPNs() {
        #expect(NetworkReader.isTunnel("utun4") && NetworkReader.isTunnel("ipsec0") && NetworkReader.isTunnel("ppp0"))
        #expect(!NetworkReader.isTunnel("en0"))
    }
}

struct NetworkTrafficTests {
    @Test func rateIsBytesOverTime() throws {
        let old = InterfaceCounters(received: 1_000, sent: 500)
        let rate = try #require(NetworkTraffic.rate(from: old, to: InterfaceCounters(received: 3_000, sent: 1_500), over: 2))
        #expect(rate.received == 1_000 && rate.sent == 500)
    }

    @Test func readingsThatMeanNothingGiveNoRate() {
        let old = InterfaceCounters(received: 1_000, sent: 500)
        #expect(NetworkTraffic.rate(from: old, to: InterfaceCounters(received: 2_000, sent: 600), over: 0.1) == nil, "too close")
        #expect(NetworkTraffic.rate(from: old, to: InterfaceCounters(received: 2_000, sent: 600), over: 30) == nil, "too long ago")
        #expect(NetworkTraffic.rate(from: old, to: InterfaceCounters(received: 10, sent: 600), over: 1) == nil, "counters reset")
    }

    @MainActor @Test func samplesKeepAMinuteOfOneInterface() {
        let traffic = NetworkTraffic()
        let start = Date(timeIntervalSince1970: 1_000_000)
        traffic.sample("en0", counters: InterfaceCounters(received: 0, sent: 0), at: start)
        #expect(traffic.samples.isEmpty, "the first reading has nothing to compare with")
        for second in 1...70 {
            traffic.sample("en0", counters: InterfaceCounters(received: UInt64(second) * 1_000, sent: UInt64(second) * 10),
                           at: start.addingTimeInterval(Double(second)))
        }
        #expect(traffic.samples.count == 61 && traffic.samples.allSatisfy { $0.received == 1_000 && $0.sent == 10 })
        traffic.sample("en1", counters: InterfaceCounters(received: 0, sent: 0), at: start.addingTimeInterval(71))
        traffic.sample("en1", counters: InterfaceCounters(received: 5_000, sent: 0), at: start.addingTimeInterval(72))
        #expect(traffic.samples.count == 1 && traffic.samples[0].received == 5_000, "another connection starts over")
    }

    @Test func countersCanBeRead() {
        // Loopback is always there.
        #expect(InterfaceCounters.read()["lo0"] != nil)
    }
}

struct PublicAddressTests {
    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "addr-fyi", withExtension: "json", subdirectory: "Fixtures/network"))
        return try Data(contentsOf: url)
    }

    @Test func addrFyiAnswersRead() throws {
        let address = try #require(PublicAddress.read(try fixture(), latency: 18.4, fetched: Date()))
        #expect(address.ip == "203.0.113.24")
        #expect(address.asn == 7029 && address.edge == "ATL")
        #expect(address.place == "Charlotte, North Carolina")
        #expect(address.provider == "Windstream Communications")
        #expect(address.latency == 18.4)
        #expect(PublicAddress.read(Data("{}".utf8), latency: nil, fetched: Date()) == nil)
        #expect(PublicAddress.read(Data("203.0.113.24".utf8), latency: nil, fetched: Date()) == nil, "plain text isn't JSON")
    }

    @Test func providerNamesLoseTheirSuffixButKeepTheirCase() {
        func provider(_ org: String) -> String? { PublicAddress(ip: "x", organization: org, fetched: Date()).provider }
        #expect(provider("Comcast Cable Communications, LLC") == "Comcast Cable Communications")
        #expect(provider("Google Fiber Inc.") == "Google Fiber")
        #expect(provider("AT&T Enterprises") == "AT&T Enterprises")
        #expect(provider("Cloudflare") == "Cloudflare")
        #expect(provider("") == nil)
    }
}

struct SystemMenuExtraTests {
    private func info(bundleID: String, identifier: String?, subrole: String = "AXMenuExtra") -> HoverInfo {
        var info = HoverInfo(pid: 1, bundleID: bundleID)
        info.role = "AXMenuBarItem"
        info.subrole = subrole
        info.identifier = identifier
        info.frame = CGRect(x: 1518, y: 4, width: 22, height: 22)
        return info
    }

    @Test func theWiFiItemIsMatchedWhereverMacOSHostsIt() {
        #expect(SystemMenuExtra(info(bundleID: "com.apple.MenuBarAgent", identifier: "com.apple.menuextra.wifi")) == .network)
        #expect(SystemMenuExtra(info(bundleID: "com.apple.controlcenter", identifier: "com.apple.menuextra.wifi")) == .network)
        #expect(MediaResolver.source(for: info(bundleID: "com.apple.MenuBarAgent", identifier: "com.apple.menuextra.wifi"))
            == .network(item: CGRect(x: 1518, y: 4, width: 22, height: 22)))
    }

    @Test func othersAreNot() {
        #expect(SystemMenuExtra(info(bundleID: "com.apple.MenuBarAgent", identifier: "com.apple.menuextra.sound")) == nil)
        #expect(SystemMenuExtra(info(bundleID: "com.example.wifitool", identifier: "com.apple.menuextra.wifi")) == nil, "only Apple's own")
        #expect(SystemMenuExtra(info(bundleID: "com.apple.MenuBarAgent", identifier: "com.apple.menuextra.wifi", subrole: "AXHostingView")) == nil)
        #expect(SystemMenuExtra(info(bundleID: "com.apple.MenuBarAgent", identifier: nil)) == nil)
    }

    @Test func itCanBeTurnedOffAndLoadsNothingFromWhatsHovered() {
        let source = MediaSource.network(item: .zero)
        #expect(PreviewFilter().allows(source))
        #expect(!PreviewFilter(network: false).allows(source))
        #expect(OtherAppsPolicy().allows(source, in: .other, keyHeld: false))
        #expect(source.menuBarItem == .zero && MediaSource.weather(item: .zero).menuBarItem == .zero)
    }
}

struct MenuBarClicksTests {
    private let wifi = CGRect(x: 1518, y: 4, width: 22, height: 22)
    private let weather = CGRect(x: 1258, y: 3, width: 69, height: 24)

    private func isOpen(_ clicks: inout MenuBarClicks, _ item: CGRect) -> Bool { clicks.menuIsOpen(for: item) }

    @Test func aClickedItemKeepsItsPopupAwayWhileItsMenuIsOpen() {
        var clicks = MenuBarClicks()
        #expect(!isOpen(&clicks, wifi))
        // Clicked before its popup appeared, or while it showed.
        clicks.clicked(at: CGPoint(x: 1529, y: 14))
        #expect(isOpen(&clicks, wifi))
        #expect(isOpen(&clicks, wifi), "still open while the cursor wanders over it")
        #expect(!isOpen(&clicks, weather), "another item's popup still shows")
        var showing = MenuBarClicks()
        showing.clicked(at: CGPoint(x: 1529, y: 14), on: wifi)
        #expect(isOpen(&showing, wifi))
    }

    @Test func theMenuClosesOnAClickElsewhereASecondClickOrEsc() {
        var elsewhere = MenuBarClicks()
        elsewhere.clicked(at: CGPoint(x: 1529, y: 14))
        _ = isOpen(&elsewhere, wifi)
        elsewhere.clicked(at: CGPoint(x: 1500, y: 200))
        #expect(!isOpen(&elsewhere, wifi))

        var again = MenuBarClicks()
        again.clicked(at: CGPoint(x: 1529, y: 14))
        _ = isOpen(&again, wifi)
        again.clicked(at: CGPoint(x: 1530, y: 12))
        #expect(!isOpen(&again, wifi))

        var escape = MenuBarClicks()
        escape.clicked(at: CGPoint(x: 1529, y: 14), on: wifi)
        escape.closed()
        #expect(!isOpen(&escape, wifi))
    }
}

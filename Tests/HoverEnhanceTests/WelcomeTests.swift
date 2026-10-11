import Foundation
import Testing
@testable import HoverEnhance

@MainActor
struct AccessibilityWatcherTests {
    /// Stands in for the system's answer.
    private final class Trust {
        var granted = false
    }

    @Test func reportsAccessTurningOnAndOff() {
        let trust = Trust()
        let watcher = AccessibilityWatcher { trust.granted }
        var changes: [Bool] = []
        watcher.onChange = { changes.append($0) }
        #expect(!watcher.isGranted)

        watcher.check()
        #expect(changes.isEmpty)

        trust.granted = true
        watcher.check()
        #expect(watcher.isGranted)
        watcher.check()
        #expect(changes == [true])

        trust.granted = false
        watcher.check()
        #expect(!watcher.isGranted)
        #expect(changes == [true, false])
    }

    @Test func startsWithTheCurrentAnswer() {
        #expect(AccessibilityWatcher { true }.isGranted)
    }
}

struct UpdatesTests {
    private let key = "fZ4NlJ+2ZPYpX53Iiex5cAeUUpGUHzULj/JI/Y4X784="

    @Test func updatesNeedAFeedAndAKey() {
        #expect(Updates.isConfigured(["SUFeedURL": "https://updates.example.com/appcast.xml", "SUPublicEDKey": key]))
        // Builds made before releases are set up have no feed yet.
        #expect(!Updates.isConfigured(["SUFeedURL": "", "SUPublicEDKey": key]))
        #expect(!Updates.isConfigured(["SUFeedURL": "https://updates.example.com/appcast.xml"]))
        // Never over plain HTTP, even with a signed feed.
        #expect(!Updates.isConfigured(["SUFeedURL": "http://updates.example.com/appcast.xml", "SUPublicEDKey": key]))
    }

    @Test func theShippedInfoPlistHasTheKey() throws {
        let info = try #require(NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any])
        #expect(info["SUPublicEDKey"] as? String == key)
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUFeedURL"] as? String == "https://github.com/jstilwell/HoverEnhance/releases/latest/download/appcast.xml")
        #expect(info["CFBundleIconFile"] as? String == "AppIcon")
    }
}

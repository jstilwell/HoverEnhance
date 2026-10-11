import AppKit
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

struct OwnWindowsTests {
    private func window(_ pid: pid_t, _ rect: CGRect, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: Int(pid), kCGWindowBounds as String: rect.dictionaryRepresentation, kCGWindowAlpha as String: alpha]
    }

    @Test func ownWindowsInFrontAreNeverInspected() {
        let browser = window(500, CGRect(x: 0, y: 0, width: 1000, height: 800))
        let about = window(42, CGRect(x: 100, y: 100, width: 460, height: 330))
        #expect(OwnWindows.areInFront(at: CGPoint(x: 200, y: 200), windows: [about, browser], ownPID: 42))
        // Beside the About window, the browser is what's there.
        #expect(!OwnWindows.areInFront(at: CGPoint(x: 900, y: 700), windows: [about, browser], ownPID: 42))
        // Another app's window in front of ours hides it.
        #expect(!OwnWindows.areInFront(at: CGPoint(x: 200, y: 200), windows: [browser, about], ownPID: 42))
    }

    @Test func invisibleWindowsOfOtherAppsDontHideOurs() {
        let overlay = window(700, CGRect(x: 0, y: 0, width: 2000, height: 2000), alpha: 0)
        let notch = window(42, CGRect(x: 190, y: 186, width: 34, height: 28))
        #expect(OwnWindows.areInFront(at: CGPoint(x: 200, y: 200), windows: [overlay, notch], ownPID: 42))
        #expect(!OwnWindows.areInFront(at: CGPoint(x: 600, y: 600), windows: [overlay, notch], ownPID: 42))
    }
}

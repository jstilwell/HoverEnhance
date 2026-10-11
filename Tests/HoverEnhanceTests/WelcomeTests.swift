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
    private func window(_ number: Int, _ pid: pid_t, _ rect: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: Int(pid), kCGWindowBounds as String: rect.dictionaryRepresentation]
    }

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let point = CGPoint(x: 900, y: 500)

    @Test func theDocksOverlayDoesntHideOurWindows() {
        // The Dock keeps an invisible window over the whole screen, in front of every app's windows.
        let dock = window(1, 100, screen)
        let about = window(2, 42, CGRect(x: 730, y: 360, width: 460, height: 362))
        let browser = window(3, 500, CGRect(x: 0, y: 30, width: 1920, height: 997))
        #expect(OwnWindows.areInFront(at: point, windows: [dock, about, browser], clickedWindow: 2, ownPID: 42))
        // Beside the About window, a click reaches the browser.
        #expect(!OwnWindows.areInFront(at: CGPoint(x: 100, y: 100), windows: [dock, about, browser], clickedWindow: 3, ownPID: 42))
    }

    @Test func ourWindowsBehindAnotherAppDontCount() {
        let browser = window(3, 500, screen)
        let settings = window(2, 42, CGRect(x: 730, y: 360, width: 540, height: 650))
        #expect(!OwnWindows.areInFront(at: point, windows: [browser, settings], clickedWindow: 3, ownPID: 42))
    }

    @Test func clickThroughWindowsOfOursCount() {
        // A click goes through the notch to the page, but accessibility finds the notch.
        let notch = window(9, 42, CGRect(x: 886, y: 486, width: 34, height: 28))
        let browser = window(3, 500, screen)
        #expect(OwnWindows.areInFront(at: point, windows: [notch, browser], clickedWindow: 3, ownPID: 42))
    }

    @Test func withoutAClickedWindowAnyOfOursCounts() {
        let browser = window(3, 500, screen)
        let about = window(2, 42, CGRect(x: 730, y: 360, width: 460, height: 362))
        #expect(OwnWindows.areInFront(at: point, windows: [browser, about], clickedWindow: nil, ownPID: 42))
        #expect(!OwnWindows.areInFront(at: point, windows: [browser], clickedWindow: nil, ownPID: 42))
    }
}

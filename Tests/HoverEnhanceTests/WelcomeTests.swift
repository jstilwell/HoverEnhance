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

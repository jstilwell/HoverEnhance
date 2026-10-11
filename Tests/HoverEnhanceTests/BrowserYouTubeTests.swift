import AppKit
import Foundation
import JavaScriptCore
import Testing
@testable import HoverEnhance

struct BrowserYouTubeScriptTests {
    private let actions: [BrowserYouTube.Action] = [.check, .status(channelID: "UC1"), .subscribe(channelID: "UC1"), .unsubscribe(channelID: "UC\"1")]

    @Test func javaScriptIsValid() throws {
        for action in actions {
            let script = BrowserYouTube.startScript(action, key: "__hoverEnhance_abc")
            // Defining a function that holds the script parses it without running it.
            let context = try #require(JSContext())
            var thrown: String?
            context.exceptionHandler = { _, exception in thrown = exception?.toString() }
            context.evaluateScript("function parseOnly() { return \(script); }")
            #expect(thrown == nil, "\(action): \(thrown ?? "")")
        }
    }

    @Test func javaScriptCarriesTheChannelSafely() {
        let script = BrowserYouTube.startScript(.unsubscribe(channelID: "UC\"1"), key: "k")
        #expect(script.contains(#"channelIds: ["UC\"1"]"#))
        #expect(script.contains("subscription/unsubscribe"))
    }

    @MainActor
    @Test func appleScriptCompilesForInstalledBrowsers() throws {
        for (bundleID, kind) in [("net.imput.helium", BrowserYouTube.Kind.chromium), ("com.apple.Safari", .safari)] {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { continue }
            let source = BrowserYouTube.appleScript(running: BrowserYouTube.startScript(.status(channelID: "UC1"), key: "k"), in: bundleID, kind: kind)
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            #expect(script?.compileAndReturnError(&error) == true, "\(bundleID): \(String(describing: error))")
        }
    }

    @Test func appleScriptStringsEscape() {
        #expect(BrowserYouTube.appleScriptLiteral(#"a "b" \s"#) == #""a \"b\" \\s""#)
    }
}

struct BrowserYouTubeOutcomeTests {
    @Test func osascriptErrorsExplainTheFix() {
        func failure(_ message: String, safari: Bool = false) -> BrowserYouTube.Failure {
            BrowserYouTube.failure(fromOsascript: message, browser: "Helium", kind: safari ? .safari : .chromium)
        }
        #expect(failure("execution error: Not authorized to send Apple events to Helium. (-1743)\n") == .automationDenied(browser: "Helium"))
        #expect(failure("execution error: Helium got an error: Executing JavaScript through AppleScript is turned off. To turn it on, from the menu bar, go to View > Developer > Allow JavaScript from Apple Events. (12)")
            == .javaScriptOff(browser: "Helium", safari: false))
        #expect(failure("execution error: Safari got an error: You must enable the 'Allow JavaScript from Apple Events' option in Safari's Develop menu to use 'do JavaScript'. (8)", safari: true)
            == .javaScriptOff(browser: "Helium", safari: true))
        #expect(failure("execution error: no YouTube tab (1001)") == .noYouTubeTab(browser: "Helium"))
        #expect(failure("execution error: not running (1002)") == .notRunning(browser: "Helium"))
        #expect(BrowserYouTube.Failure.javaScriptOff(browser: "Helium", safari: false).errorDescription
            == "In Helium, turn on View → Developer → Allow JavaScript from Apple Events.")
    }

    @Test func pageAnswersParse() throws {
        #expect(try BrowserYouTube.parse("null", browser: "Helium") == nil)
        #expect(try BrowserYouTube.parse(#"{"done":false}"#, browser: "Helium") == nil)
        #expect(try BrowserYouTube.parse(#"{"done":true,"subscribed":true}"#, browser: "Helium") == BrowserYouTube.Result(subscribed: true))
        #expect(try BrowserYouTube.parse(#"{"done":true,"subscribed":null}"#, browser: "Helium") == BrowserYouTube.Result(subscribed: nil))
        #expect(throws: BrowserYouTube.Failure.signedOut(browser: "Helium")) {
            try BrowserYouTube.parse(#"{"done":true,"error":"signed-out"}"#, browser: "Helium")
        }
        #expect(throws: BrowserYouTube.Failure.youtube("HTTP 401")) {
            try BrowserYouTube.parse(#"{"done":true,"error":"HTTP 401"}"#, browser: "Helium")
        }
    }

    @Test func onlyScriptableBrowsersQualify() {
        #expect(BrowserYouTube.Kind(bundleID: "com.apple.Safari") == .safari)
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.imput.helium") != nil {
            #expect(BrowserYouTube.Kind(bundleID: "net.imput.helium") == .chromium)
        }
        // Electron apps are Chromium inside but have no scripting dictionary.
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.tinyspeck.slackmacgap") != nil {
            #expect(BrowserYouTube.Kind(bundleID: "com.tinyspeck.slackmacgap") == nil)
        }
        #expect(BrowserYouTube.Kind(bundleID: "org.mozilla.firefox") == nil)
    }
}

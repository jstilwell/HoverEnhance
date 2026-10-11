import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt offering to open the Accessibility settings pane.
    static func request() {
        // Value of kAXTrustedCheckOptionPrompt, a mutable global that Swift 6 won't let us read.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

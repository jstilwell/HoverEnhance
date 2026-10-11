import AppKit
import Observation
import Sparkle

/// Updates through Sparkle, from the appcast Info.plist names (`SUFeedURL`), which must be signed with
/// the key whose public half is `SUPublicEDKey`. A build without both, such as one made from source
/// before releases are set up, doesn't update itself.
@MainActor @Observable
final class Updates: NSObject {
    static let shared = Updates()

    /// Whether this build updates itself at all.
    private(set) var isAvailable = false
    /// A version a scheduled check found, which the menu offers until the user looks at it.
    private(set) var waitingVersion: String?
    var checksAutomatically = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil, Self.isConfigured(Bundle.main.infoDictionary ?? [:]) else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        isAvailable = true
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
    }

    /// Whether `info` names a feed and the key its updates are signed with.
    nonisolated static func isConfigured(_ info: [String: Any]) -> Bool {
        let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        let key = info["SUPublicEDKey"] as? String
        return feed?.scheme == "https" && key?.isEmpty == false
    }

    /// Debug builds come from source and check only when asked, so they're never offered a release
    /// over themselves.
    static var checksOnlyWhenAsked: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Checks now, showing Sparkle's window with the result.
    func checkForUpdates() {
        // A menu bar app isn't in front on its own, and Sparkle's window would open behind others.
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

extension Updates: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if Self.checksOnlyWhenAsked, updateCheck == .updatesInBackground {
            throw NSError(domain: "HoverEnhance.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Debug builds don't check on their own."])
        }
    }
}

/// Gentle reminders: a menu bar app is never the active app, so an update found in the background is
/// offered in the menu (with a dot on the icon) rather than in a window that would open behind others.
extension Updates: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Sparkle shows it at once only when it would come up in front, as just after launch.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { waitingVersion = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        waitingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        waitingVersion = nil
    }
}

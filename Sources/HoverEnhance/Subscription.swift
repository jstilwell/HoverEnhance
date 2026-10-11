import Foundation
import Observation

extension Notification.Name {
    /// Asks the app to show Settings; the object is the tab's title.
    static let showSettingsTab = Notification.Name("HoverEnhance.showSettingsTab")
    /// Asks the app to show the welcome window's guide to Accessibility access.
    static let showAccessibilityGuide = Notification.Name("HoverEnhance.showAccessibilityGuide")
}

/// Whether the signed-in account subscribes to one channel, and the action to change it.
@MainActor @Observable
final class Subscription {
    enum Status: Equatable {
        case signedOut, checking, subscribed(id: String), notSubscribed, changing
        /// The client's Google Cloud project doesn't have the YouTube Data API on; `fix` turns it on.
        case apiOff(fix: URL)
    }

    let channelID: String
    private(set) var status: Status = .checking
    private(set) var error: String?

    /// Recent answers, so hovering around a page doesn't spend quota re-asking. Session only.
    private static var known: [String: (subscriptionID: String?, time: Date)] = [:]
    private static let knownLifetime: TimeInterval = 10 * 60

    private let account = YouTubeAccount.shared

    init(channelID: String) {
        self.channelID = channelID
    }

    func load() async {
        guard account.status == .signedIn else {
            status = .signedOut
            return
        }
        if let known = Self.known[channelID], Date().timeIntervalSince(known.time) < Self.knownLifetime {
            status = known.subscriptionID.map { .subscribed(id: $0) } ?? .notSubscribed
            return
        }
        status = .checking
        do {
            let id = try await YouTubeAPI.subscriptionID(to: channelID, token: account.accessToken())
            remember(id)
        } catch {
            fail(error, fallback: account.status == .signedIn ? .notSubscribed : .signedOut)
        }
    }

    func toggle() async {
        let before = status
        status = .changing
        error = nil
        do {
            let token = try await account.accessToken()
            switch before {
            case .subscribed(let id):
                try await YouTubeAPI.unsubscribe(id, token: token)
                remember(nil)
            case .notSubscribed:
                do {
                    let id = try await YouTubeAPI.subscribe(to: channelID, token: token)
                    remember(id ?? "")
                } catch let failure as YouTubeAPI.Failure where failure.reason == "subscriptionDuplicate" {
                    remember(try await YouTubeAPI.subscriptionID(to: channelID, token: token))
                }
            default:
                status = before
            }
        } catch {
            fail(error, fallback: account.status == .signedIn ? before : .signedOut)
        }
    }

    private func remember(_ subscriptionID: String?) {
        Self.known[channelID] = (subscriptionID, Date())
        status = subscriptionID.map { .subscribed(id: $0) } ?? .notSubscribed
    }

    private func fail(_ failure: Error, fallback: Status) {
        error = failure.localizedDescription
        if let failure = failure as? YouTubeAPI.Failure, failure.isAPIDisabled {
            status = .apiOff(fix: failure.activationURL ?? YouTubeAPI.consoleURL)
        } else {
            status = fallback
        }
    }
}

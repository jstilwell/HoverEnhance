import Foundation
import Observation

extension Notification.Name {
    /// Asks the app to show Settings; the object is the tab's title.
    static let showSettingsTab = Notification.Name("HoverEnhance.showSettingsTab")
}

/// Whether the user subscribes to one channel, and the action to change it, through whichever
/// method Settings → Accounts picks.
@MainActor @Observable
final class Subscription {
    enum Status: Equatable {
        /// Signed out of the API, or the browser isn't set up; the button leads to Settings.
        case needsSetup
        case checking
        /// `id` is the API's subscription ID, needed to unsubscribe; nil in browser mode.
        case subscribed(id: String?)
        case notSubscribed
        case changing
    }

    let channelID: String
    /// The browser the card was opened from, for browser mode.
    let browser: String?
    private(set) var status: Status = .checking
    private(set) var error: String?

    /// Recent answers, so hovering around a page doesn't re-ask. Session only.
    private static var known: [String: (status: Status, time: Date)] = [:]
    private static let knownLifetime: TimeInterval = 10 * 60

    private let account = YouTubeAccount.shared

    init(channelID: String, browser: String?) {
        self.channelID = channelID
        self.browser = browser
    }

    var method: YouTubeAccount.Method { account.method }

    func load() async {
        if account.method == .api, account.status != .signedIn {
            status = .needsSetup
            return
        }
        if let known = Self.known[channelID], Date().timeIntervalSince(known.time) < Self.knownLifetime {
            status = known.status
            return
        }
        status = .checking
        do {
            switch account.method {
            case .api:
                let id = try await YouTubeAPI.subscriptionID(to: channelID, token: account.accessToken())
                remember(id.map { .subscribed(id: $0) } ?? .notSubscribed)
            case .browser:
                let subscribed = try await BrowserYouTube.isSubscribed(to: channelID, in: browser ?? "")
                // YouTube's answer may not say; Subscribe is harmless if already subscribed.
                remember(subscribed == true ? .subscribed(id: nil) : .notSubscribed)
            }
        } catch {
            fail(error, fallback: .needsSetup)
        }
    }

    func toggle() async {
        let before = status
        guard before == .notSubscribed || before.isSubscribed else { return }
        status = .changing
        error = nil
        do {
            switch account.method {
            case .api:
                let token = try await account.accessToken()
                if case .subscribed(let id?) = before {
                    try await YouTubeAPI.unsubscribe(id, token: token)
                    remember(.notSubscribed)
                } else {
                    do {
                        let id = try await YouTubeAPI.subscribe(to: channelID, token: token)
                        remember(.subscribed(id: id))
                    } catch let failure as YouTubeAPI.Failure where failure.reason == "subscriptionDuplicate" {
                        let id = try await YouTubeAPI.subscriptionID(to: channelID, token: token)
                        remember(.subscribed(id: id))
                    }
                }
            case .browser:
                let subscribe = !before.isSubscribed
                try await BrowserYouTube.setSubscribed(subscribe, to: channelID, in: browser ?? "")
                remember(subscribe ? .subscribed(id: nil) : .notSubscribed)
            }
        } catch {
            fail(error, fallback: account.method == .api && account.status != .signedIn ? .needsSetup : before)
        }
    }

    private func remember(_ status: Status) {
        Self.known[channelID] = (status, Date())
        self.status = status
    }

    private func fail(_ failure: Error, fallback: Status) {
        error = failure.localizedDescription
        status = fallback
    }
}

extension Subscription.Status {
    var isSubscribed: Bool {
        if case .subscribed = self { true } else { false }
    }
}

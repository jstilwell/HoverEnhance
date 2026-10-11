import AppKit
import Observation

/// The user's YouTube sign-in, through their own Google Cloud OAuth client. The client secret and
/// refresh token live in the Keychain; the client ID and account name in UserDefaults.
@MainActor @Observable
final class YouTubeAccount {
    static let shared = YouTubeAccount()

    enum Status: Equatable {
        case signedOut, signingIn, signedIn
    }

    /// Whether signed-in calls to YouTube actually work, as last checked.
    enum Access: Equatable {
        case unknown, checking, working
        /// `fix` opens the page that solves it, such as turning the API on for the project.
        case failing(message: String, fix: URL?)
    }

    private enum Key {
        static let clientID = "youtubeClientID"
        static let accountName = "youtubeAccountName"
        static let clientSecret = "youtube.clientSecret"
        static let refreshToken = "youtube.refreshToken"
    }

    var clientID: String { didSet { UserDefaults.standard.set(clientID, forKey: Key.clientID) } }
    /// Saved to the Keychain when sign-in succeeds.
    var clientSecret: String
    private(set) var status: Status
    private(set) var accountName: String?
    private(set) var lastError: String?
    private(set) var access: Access = .unknown

    @ObservationIgnored private var tokens: GoogleOAuth.Tokens?

    init() {
        clientID = UserDefaults.standard.string(forKey: Key.clientID) ?? ""
        clientSecret = Keychain.string(for: Key.clientSecret) ?? ""
        status = Keychain.string(for: Key.refreshToken) == nil ? .signedOut : .signedIn
        accountName = UserDefaults.standard.string(forKey: Key.accountName)
    }

    var canSignIn: Bool {
        status != .signingIn && !trimmedID.isEmpty && !trimmedSecret.isEmpty
    }

    private var trimmedID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSecret: String { clientSecret.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Opens Google's sign-in page in the browser and waits for it to come back.
    func signIn() async {
        guard canSignIn else { return }
        status = .signingIn
        lastError = nil
        do {
            let redirect = try await LoopbackRedirect.start()
            defer { redirect.stop() }
            let verifier = GoogleOAuth.codeVerifier()
            let state = UUID().uuidString
            NSWorkspace.shared.open(GoogleOAuth.authorizationURL(
                clientID: trimmedID, redirectURI: redirect.redirectURI,
                challenge: GoogleOAuth.codeChallenge(for: verifier), state: state
            ))
            let query = try await redirect.callback(timeout: .seconds(300))
            guard query["state"] == state else { throw GoogleOAuth.Failure.stateMismatch }
            if let error = query["error"] { throw GoogleOAuth.Failure.google(code: error, description: nil) }
            let tokens = try await GoogleOAuth.exchange(
                code: query["code"] ?? "", verifier: verifier, clientID: trimmedID, secret: trimmedSecret, redirectURI: redirect.redirectURI
            )
            guard let refreshToken = tokens.refreshToken else { throw GoogleOAuth.Failure.noRefreshToken }

            Keychain.set(trimmedSecret, for: Key.clientSecret)
            Keychain.set(refreshToken, for: Key.refreshToken)
            self.tokens = tokens
            status = .signedIn
            await checkAccess()
        } catch {
            status = .signedOut
            lastError = error.localizedDescription
        }
        // Come back from the browser to Settings.
        NSApp.activate()
    }

    /// Makes a small API call to confirm YouTube access works, and learns the account's name.
    func checkAccess() async {
        guard status == .signedIn, access != .checking else { return }
        access = .checking
        do {
            accountName = try await YouTubeAPI.myChannelTitle(token: accessToken())
            UserDefaults.standard.set(accountName, forKey: Key.accountName)
            access = .working
        } catch {
            let failure = error as? YouTubeAPI.Failure
            let fix = failure?.isAPIDisabled == true ? (failure?.activationURL ?? YouTubeAPI.consoleURL) : nil
            access = .failing(message: error.localizedDescription, fix: fix)
        }
    }

    func signOut() async {
        let refreshToken = Keychain.string(for: Key.refreshToken)
        forget()
        if let refreshToken { await GoogleOAuth.revoke(refreshToken) }
    }

    /// A current access token, refreshed when it's about to expire.
    func accessToken() async throws -> String {
        if let tokens, tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
        guard let refreshToken = Keychain.string(for: Key.refreshToken) else {
            throw GoogleOAuth.Failure.google(code: "invalid_grant", description: nil)
        }
        do {
            let fresh = try await GoogleOAuth.refresh(refreshToken, clientID: trimmedID, secret: trimmedSecret)
            tokens = fresh
            return fresh.accessToken
        } catch GoogleOAuth.Failure.google(code: "invalid_grant", _) {
            // Revoked, expired, or the client was deleted: signed out for real.
            forget()
            lastError = GoogleOAuth.Failure.google(code: "invalid_grant", description: nil).localizedDescription
            throw GoogleOAuth.Failure.google(code: "invalid_grant", description: nil)
        }
    }

    private func forget() {
        Keychain.set(nil, for: Key.refreshToken)
        tokens = nil
        status = .signedOut
        access = .unknown
        accountName = nil
        UserDefaults.standard.removeObject(forKey: Key.accountName)
    }
}

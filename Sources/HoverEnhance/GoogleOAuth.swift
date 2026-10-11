import CryptoKit
import Foundation
import Network

/// Google's OAuth for installed apps: the browser signs in, comes back to a loopback address with a
/// code, and the code (with a PKCE verifier) is traded for tokens.
/// https://developers.google.com/identity/protocols/oauth2/native-app
enum GoogleOAuth {
    static let youtubeScope = "https://www.googleapis.com/auth/youtube"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!

    struct Tokens: Sendable, Equatable {
        let accessToken: String
        let expiresAt: Date
        /// Only on the first exchange; refreshes keep the same one.
        let refreshToken: String?
    }

    enum Failure: LocalizedError, Equatable {
        case google(code: String, description: String?)
        case unreadableResponse
        case stateMismatch
        case noRefreshToken
        case timedOut

        var errorDescription: String? {
            switch self {
            case .google("invalid_client", _): "Google didn't accept the client ID or secret."
            case .google("invalid_grant", _): "The sign-in has expired or was revoked. Sign in again."
            case .google("access_denied", _): "Sign-in was cancelled."
            case .google(let code, let description): description.map { "Google: \($0)" } ?? "Google returned \(code)."
            case .unreadableResponse: "Google's response couldn't be read."
            case .stateMismatch: "The sign-in response didn't match this request. Try again."
            case .noRefreshToken: "Google didn't grant ongoing access. Remove HoverEnhance at myaccount.google.com/permissions and sign in again."
            case .timedOut: "Sign-in timed out."
            }
        }
    }

    // MARK: - PKCE

    /// 64 characters from the URL-safe alphabet, as RFC 7636 asks for.
    static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Requests

    static func authorizationURL(clientID: String, redirectURI: String, challenge: String, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: youtubeScope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Ask for a refresh token, and ask again even if this app was approved before.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    static func exchange(code: String, verifier: String, clientID: String, secret: String, redirectURI: String) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "authorization_code", "code": code, "code_verifier": verifier,
            "client_id": clientID, "client_secret": secret, "redirect_uri": redirectURI,
        ])
    }

    static func refresh(_ refreshToken: String, clientID: String, secret: String) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID, "client_secret": secret,
        ])
    }

    static func revoke(_ token: String) async {
        var request = URLRequest(url: revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["token": token])
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try tokens(from: data)
    }

    static func tokens(from data: Data, now: Date = Date()) throws -> Tokens {
        struct Response: Decodable {
            let access_token: String?
            let expires_in: Double?
            let refresh_token: String?
            let error: String?
            let error_description: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw Failure.unreadableResponse }
        if let error = response.error { throw Failure.google(code: error, description: response.error_description) }
        guard let token = response.access_token else { throw Failure.unreadableResponse }
        return Tokens(accessToken: token, expiresAt: now.addingTimeInterval(response.expires_in ?? 3600), refreshToken: response.refresh_token)
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }
}

/// A one-shot HTTP listener on 127.0.0.1 that catches the browser's return from Google's sign-in
/// page and answers with a page saying it's done. Loopback only, so nothing on the network can reach it.
final class LoopbackRedirect: @unchecked Sendable {
    private let listener: NWListener
    /// All state below is touched only on this queue.
    private let queue = DispatchQueue(label: "HoverEnhance.oauth-redirect")
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<[String: String], Error>?
    private var received: [String: String]?

    private(set) var port: UInt16 = 0
    var redirectURI: String { "http://127.0.0.1:\(port)" }

    private init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    static func start() async throws -> LoopbackRedirect {
        let redirect = try LoopbackRedirect()
        redirect.port = try await withCheckedThrowingContinuation { continuation in
            redirect.queue.async { redirect.begin(continuation) }
        }
        return redirect
    }

    private func begin(_ continuation: CheckedContinuation<UInt16, Error>) {
        readyContinuation = continuation
        listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    /// The query parameters the browser came back with.
    func callback(timeout: Duration) async throws -> [String: String] {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled else { return }
            queue.async { self.finish(.failure(GoogleOAuth.Failure.timedOut)) }
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let received = self.received {
                    continuation.resume(returning: received)
                } else {
                    self.callbackContinuation = continuation
                }
            }
        }
    }

    func stop() {
        queue.async { self.listener.cancel() }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            readyContinuation?.resume(returning: listener.port?.rawValue ?? 0)
            readyContinuation = nil
        case .failed(let error):
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
            finish(.failure(error))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let query = Self.query(fromRequest: data ?? Data())
            // Browsers also ask for /favicon.ico; only the sign-in response counts.
            guard let query, query["code"] != nil || query["error"] != nil else {
                Self.respond(on: connection, status: "404 Not Found", body: "")
                return
            }
            let succeeded = query["code"] != nil
            Self.respond(on: connection, status: "200 OK", body: Self.page(succeeded: succeeded))
            finish(.success(query))
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        if case .success(let query) = result, received == nil { received = query }
        guard let continuation = callbackContinuation else { return }
        callbackContinuation = nil
        continuation.resume(with: result)
    }

    /// The query of an HTTP request line like "GET /?code=…&state=… HTTP/1.1".
    static func query(fromRequest data: Data) -> [String: String]? {
        guard let line = String(decoding: data, as: UTF8.self).split(separator: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let items = URLComponents(string: "http://127.0.0.1" + parts[1])?.queryItems else { return nil }
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    private static func respond(on connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func page(succeeded: Bool) -> String {
        let (title, detail) = succeeded
            ? ("Signed in to YouTube", "You can close this tab and go back to HoverEnhance.")
            : ("Sign-in didn't finish", "Go back to HoverEnhance's settings to try again.")
        return """
        <!doctype html><meta charset="utf-8"><title>HoverEnhance</title>
        <body style="font: 15px -apple-system, sans-serif; text-align: center; margin-top: 20vh; color: #333">
        <h2>\(title)</h2><p>\(detail)</p></body>
        """
    }
}

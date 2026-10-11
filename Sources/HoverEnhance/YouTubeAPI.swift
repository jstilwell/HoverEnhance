import Foundation

/// The YouTube Data API calls creator cards use. https://developers.google.com/youtube/v3/docs
/// Quota: a subscription check costs 1 unit, subscribing or unsubscribing 50, of 10,000 a day.
enum YouTubeAPI {
    private static let base = URL(string: "https://www.googleapis.com/youtube/v3/")!
    /// The API's page in Google Cloud Console, for when Google doesn't name the project.
    static let consoleURL = URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")!

    struct Failure: LocalizedError, Equatable {
        let status: Int
        let reason: String?
        let message: String?
        /// Google's link to turn the API on for the client's own project, when that's the problem.
        var activationURL: URL? = nil

        /// The client's Google Cloud project doesn't have the YouTube Data API turned on.
        var isAPIDisabled: Bool {
            reason == "accessNotConfigured" || reason == "SERVICE_DISABLED"
        }

        var errorDescription: String? {
            if isAPIDisabled { return "The YouTube Data API v3 isn't turned on for your Google Cloud project." }
            return switch reason {
            case "quotaExceeded": "YouTube's daily limit for your client is used up. It resets at midnight Pacific time."
            case "subscriptionDuplicate": "You're already subscribed."
            case "subscriptionForbidden": "YouTube doesn't allow subscribing to this channel."
            default: message ?? "YouTube returned an error (\(status))."
            }
        }
    }

    /// The signed-in account's own channel title, to show who's signed in.
    static func myChannelTitle(token: String) async throws -> String? {
        let data = try await send("GET", "channels", query: ["part": "snippet", "mine": "true"], token: token)
        return items(in: data).first.flatMap { ($0["snippet"] as? [String: Any])?["title"] as? String }
    }

    /// The ID of the signed-in account's subscription to `channelID`, or nil if not subscribed.
    static func subscriptionID(to channelID: String, token: String) async throws -> String? {
        let data = try await send("GET", "subscriptions", query: ["part": "id", "mine": "true", "forChannelId": channelID], token: token)
        return items(in: data).first?["id"] as? String
    }

    /// Subscribes and returns the new subscription's ID.
    static func subscribe(to channelID: String, token: String) async throws -> String? {
        let body = ["snippet": ["resourceId": ["kind": "youtube#channel", "channelId": channelID]]]
        let data = try await send("POST", "subscriptions", query: ["part": "snippet"], body: body, token: token)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
    }

    static func unsubscribe(_ subscriptionID: String, token: String) async throws {
        _ = try await send("DELETE", "subscriptions", query: ["id": subscriptionID], token: token)
    }

    // MARK: - Plumbing

    static func request(_ method: String, _ path: String, query: [String: String], body: [String: Any]? = nil, token: String) -> URLRequest {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func send(_ method: String, _ path: String, query: [String: String], body: [String: Any]? = nil, token: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(method, path, query: query, body: body, token: token))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw failure(status: status, data: data) }
        return data
    }

    /// Google's error body: {"error": {"code": 403, "message": "…", "errors": [{"reason": "quotaExceeded"}],
    /// "details": [{"reason": "SERVICE_DISABLED", "metadata": {"activationUrl": "…"}}]}}.
    static func failure(status: Int, data: Data) -> Failure {
        let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
        let details = error?["details"] as? [[String: Any]] ?? []
        let reason = (error?["errors"] as? [[String: Any]])?.first?["reason"] as? String ?? details.first?["reason"] as? String
        let message = error?["message"] as? String
        // The link to turn the API on is in the error's metadata, and also in its message.
        let activation = details.lazy.compactMap { ($0["metadata"] as? [String: Any])?["activationUrl"] as? String }.first
            ?? message?.firstMatch(of: /https:\/\/console\.developers\.google\.com\/apis\/api\/youtube\.googleapis\.com\/\S*project=\d+/).map { String($0.output) }
        return Failure(status: status, reason: reason, message: message, activationURL: activation.flatMap(URL.init(string:)))
    }

    private static func items(in data: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["items"] as? [[String: Any]] ?? []
    }
}

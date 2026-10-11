import Foundation

/// The YouTube Data API calls creator cards use. https://developers.google.com/youtube/v3/docs
/// Quota: a subscription check costs 1 unit, subscribing or unsubscribing 50, of 10,000 a day.
enum YouTubeAPI {
    private static let base = URL(string: "https://www.googleapis.com/youtube/v3/")!

    struct Failure: LocalizedError, Equatable {
        let status: Int
        let reason: String?
        let message: String?

        var errorDescription: String? {
            switch reason {
            case "quotaExceeded": "YouTube's daily limit for your client is used up. It resets at midnight Pacific time."
            case "subscriptionDuplicate": "You're already subscribed."
            case "subscriptionForbidden": "YouTube doesn't allow subscribing to this channel."
            case "accessNotConfigured", "SERVICE_DISABLED": "Enable the YouTube Data API v3 for your Google Cloud project."
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

    /// Google's error body: {"error": {"code": 403, "message": "…", "errors": [{"reason": "quotaExceeded"}]}}.
    static func failure(status: Int, data: Data) -> Failure {
        let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
        let reason = (error?["errors"] as? [[String: Any]])?.first?["reason"] as? String
            ?? ((error?["details"] as? [[String: Any]])?.first?["reason"] as? String)
        return Failure(status: status, reason: reason, message: error?["message"] as? String)
    }

    private static func items(in data: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["items"] as? [[String: Any]] ?? []
    }
}

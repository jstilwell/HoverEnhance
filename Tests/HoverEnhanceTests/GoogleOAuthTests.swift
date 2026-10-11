import Foundation
import Testing
@testable import HoverEnhance

struct GoogleOAuthTests {
    @Test func pkceMatchesTheRFCExample() {
        // RFC 7636, appendix B.
        #expect(GoogleOAuth.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = GoogleOAuth.codeVerifier()
        #expect(verifier.count == 64)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func authorizationURLAsksForOfflineYouTubeAccess() throws {
        let url = GoogleOAuth.authorizationURL(clientID: "id.apps.googleusercontent.com", redirectURI: "http://127.0.0.1:5123", challenge: "abc", state: "s1")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "accounts.google.com")
        #expect(query["redirect_uri"] == "http://127.0.0.1:5123")
        #expect(query["scope"] == "https://www.googleapis.com/auth/youtube")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["access_type"] == "offline")
        #expect(query["state"] == "s1")
    }

    @Test func tokenResponses() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let ok = try GoogleOAuth.tokens(from: Data(#"{"access_token":"ya29.x","expires_in":3599,"refresh_token":"1//r","token_type":"Bearer"}"#.utf8), now: now)
        #expect(ok == GoogleOAuth.Tokens(accessToken: "ya29.x", expiresAt: Date(timeIntervalSince1970: 4599), refreshToken: "1//r"))
        #expect(throws: GoogleOAuth.Failure.google(code: "invalid_client", description: "Unauthorized")) {
            try GoogleOAuth.tokens(from: Data(#"{"error":"invalid_client","error_description":"Unauthorized"}"#.utf8))
        }
        #expect(GoogleOAuth.Failure.google(code: "invalid_client", description: nil).errorDescription == "Google didn't accept the client ID or secret.")
    }
}

struct LoopbackRedirectTests {
    @Test func requestLinesParse() {
        #expect(LoopbackRedirect.query(fromRequest: Data("GET /?code=4/0Ab&scope=x&state=s1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8))
            == ["code": "4/0Ab", "scope": "x", "state": "s1"])
        #expect(LoopbackRedirect.query(fromRequest: Data("POST / HTTP/1.1\r\n\r\n".utf8)) == nil)
    }

    @Test func catchesTheBrowsersReturn() async throws {
        let redirect = try await LoopbackRedirect.start()
        defer { redirect.stop() }
        #expect(redirect.port > 0)

        let favicon = try await URLSession.shared.data(from: URL(string: "\(redirect.redirectURI)/favicon.ico")!)
        #expect((favicon.1 as? HTTPURLResponse)?.statusCode == 404)

        async let callback = redirect.callback(timeout: .seconds(5))
        let (page, response) = try await URLSession.shared.data(from: URL(string: "\(redirect.redirectURI)/?code=abc&state=s1")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: page, as: UTF8.self).contains("Signed in to YouTube"))
        #expect(try await callback == ["code": "abc", "state": "s1"])
    }

    @Test func givesUpAfterTheTimeout() async throws {
        let redirect = try await LoopbackRedirect.start()
        defer { redirect.stop() }
        await #expect(throws: GoogleOAuth.Failure.timedOut) {
            try await redirect.callback(timeout: .milliseconds(100))
        }
    }
}

struct YouTubeAPITests {
    @Test func requestsCarryTheTokenAndBody() throws {
        let request = YouTubeAPI.request("POST", "subscriptions", query: ["part": "snippet"],
                                         body: ["snippet": ["resourceId": ["kind": "youtube#channel", "channelId": "UC1"]]], token: "t0k")
        #expect(request.url?.absoluteString == "https://www.googleapis.com/youtube/v3/subscriptions?part=snippet")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: [String: [String: String]]] })
        #expect(body["snippet"]?["resourceId"]?["channelId"] == "UC1")
    }

    @Test func disabledAPILinksToTheProjectsEnablePage() throws {
        let body = #"""
        {"error": {"code": 403,
          "message": "YouTube Data API v3 has not been used in project 123456789012 before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/youtube.googleapis.com/overview?project=123456789012 then retry. If you enabled this API recently, wait a few minutes for the action to propagate to our systems and retry.",
          "errors": [{"message": "…", "domain": "usageLimits", "reason": "accessNotConfigured", "extendedHelp": "https://console.developers.google.com"}],
          "status": "PERMISSION_DENIED",
          "details": [{"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "SERVICE_DISABLED", "domain": "googleapis.com",
            "metadata": {"consumer": "projects/123456789012", "service": "youtube.googleapis.com",
              "activationUrl": "https://console.developers.google.com/apis/api/youtube.googleapis.com/overview?project=123456789012"}}]}}
        """#
        let failure = YouTubeAPI.failure(status: 403, data: Data(body.utf8))
        #expect(failure.isAPIDisabled)
        #expect(failure.activationURL?.absoluteString == "https://console.developers.google.com/apis/api/youtube.googleapis.com/overview?project=123456789012")
        #expect(failure.errorDescription == "The YouTube Data API v3 isn't turned on for your Google Cloud project.")

        // Without the metadata, the link still comes from the message.
        let terse = #"{"error": {"code": 403, "message": "Enable it by visiting https://console.developers.google.com/apis/api/youtube.googleapis.com/overview?project=42 then retry.", "errors": [{"reason": "accessNotConfigured"}]}}"#
        #expect(YouTubeAPI.failure(status: 403, data: Data(terse.utf8)).activationURL?.absoluteString
            == "https://console.developers.google.com/apis/api/youtube.googleapis.com/overview?project=42")
    }

    @Test func errorsReadPlainly() {
        let quota = #"{"error":{"code":403,"message":"The request cannot be completed because you have exceeded your quota.","errors":[{"reason":"quotaExceeded","domain":"youtube.quota"}]}}"#
        let failure = YouTubeAPI.failure(status: 403, data: Data(quota.utf8))
        #expect(failure.reason == "quotaExceeded")
        #expect(failure.errorDescription?.hasPrefix("YouTube's daily limit") == true)
        #expect(YouTubeAPI.failure(status: 500, data: Data()).errorDescription == "YouTube returned an error (500).")
    }
}

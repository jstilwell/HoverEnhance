import WebKit

/// Loads pages in an offscreen WebKit view, for sites that only serve content to a real browser
/// engine (Reddit answers scripted requests with a JavaScript check). Cookies the page sets are
/// shared with URLSession, so later plain requests to that site get through.
@MainActor
final class WebPageLoader {
    static let shared = WebPageLoader()

    private let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900))
    /// Bumped per load; an older load still polling gives up when it sees a newer one.
    private var generation = 0

    /// The outer HTML of the first element matching `selector` once the page has one, or nil if it
    /// doesn't appear within `timeout`.
    func html(at url: URL, selector: String, timeout: Duration = .seconds(10)) async -> String? {
        generation += 1
        let mine = generation
        webView.load(URLRequest(url: url))
        defer { if generation == mine { webView.stopLoading() } }

        let script = "document.querySelector(\(Self.javaScriptString(selector)))?.outerHTML ?? null"
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, generation == mine else { return nil }
            if let html = try? await webView.evaluateJavaScript(script) as? String {
                await shareCookies(for: url)
                return html
            }
        }
        return nil
    }

    /// Cookies and storage the offscreen view and the embedded players have collected.
    static func clearWebsiteData() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    private func shareCookies(for url: URL) async {
        guard let host = url.host() else { return }
        let domain = host.split(separator: ".").suffix(2).joined(separator: ".")
        for cookie in await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        where cookie.domain.hasSuffix(domain) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private static func javaScriptString(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [string])
        return data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "''"
    }
}

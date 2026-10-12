import WebKit

/// Plays embeds in a web view. The most recent one stays alive, paused, for a few minutes after its
/// preview closes, so hovering the same link again picks up where it left off. Links clicked in a
/// player, such as its title or "Watch on YouTube", open in the browser.
@MainActor
final class EmbedPlayer: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var current: (embed: Embed, view: WKWebView)?
    /// How long a paused player is kept. Its web content process holds a hundred megabytes or more.
    private static let pausedPlayerLifetime: Duration = .seconds(180)
    private var discardLater: Task<Void, Never>?

    func view(for embed: Embed) -> WKWebView? {
        discardLater?.cancel()
        discardLater = nil
        if let current, current.embed == embed {
            current.view.setAllMediaPlaybackSuspended(false)
            return current.view
        }
        discard()
        guard let url = embed.playerURL(muted: AppSettings.shared.videosStartMuted) else { return nil }

        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Some players (Vimeo) refuse browsers they don't recognize, and a bare WebKit view leaves
        // out the "Version/… Safari/…" that Safari, the same engine, sends.
        configuration.applicationNameForUserAgent = Self.safariUserAgentSuffix
        // Players don't need AirPlay discovery or WebRTC, and both reach into the local network
        // (WebRTC is also a favorite of fingerprinting scripts), which makes macOS prompt for access.
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.userContentController.addUserScript(Self.disableWebRTC)
        let view = WKWebView(frame: CGRect(origin: .zero, size: embed.size), configuration: configuration)
        view.underPageBackgroundColor = .black
        view.navigationDelegate = self
        view.uiDelegate = self
        view.loadHTMLString(Self.page(embedding: url), baseURL: Embed.origin)
        current = (embed, view)
        return view
    }

    // MARK: - Links in players

    /// The player's own frame goes where the player takes it. The page around it stays the page it was
    /// loaded as: a clicked link that would leave it, for that page or a new window, opens in the
    /// browser, and a script in the player can't send it anywhere else.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame != false else { return .allow }
        if navigationAction.navigationType != .linkActivated, Self.isPlayerPage(navigationAction.request.url) { return .allow }
        if navigationAction.navigationType == .linkActivated { openInBrowser(navigationAction) }
        return .cancel
    }

    /// The page the player is embedded in, as `view(for:)` loads it.
    nonisolated static func isPlayerPage(_ url: URL?) -> Bool {
        url?.scheme == Embed.origin.scheme && url?.host() == Embed.origin.host() && url?.path() == Embed.origin.path()
    }

    /// New windows the player asks for. Only clicked links open; pop-ups a script opens on its own don't.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated { openInBrowser(navigationAction) }
        return nil
    }

    private func openInBrowser(_ navigationAction: WKNavigationAction) {
        guard let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Pauses the current embed without losing its place, for a while.
    func suspend() {
        guard let current else { return }
        current.view.setAllMediaPlaybackSuspended(true)
        guard discardLater == nil else { return }
        discardLater = Task { [weak self] in
            try? await Task.sleep(for: Self.pausedPlayerLifetime)
            guard !Task.isCancelled else { return }
            self?.discard()
        }
    }

    private func discard() {
        discardLater?.cancel()
        discardLater = nil
        current?.view.stopLoading()
        current?.view.removeFromSuperview()
        current = nil
    }

    private static let disableWebRTC = WKUserScript(
        source: """
        for (const name of ["RTCPeerConnection", "webkitRTCPeerConnection", "RTCDataChannel"]) {
          try { Object.defineProperty(window, name, { value: undefined, configurable: false }); } catch {}
        }
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    private static let safariUserAgentSuffix: String = {
        let safari = Bundle(url: URL(fileURLWithPath: "/Applications/Safari.app"))
        let version = safari?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "18.0"
        return "Version/\(version) Safari/605.1.15"
    }()

    /// The player in a full-window iframe. Loading it under `Embed.origin` gives it a Referer.
    private static func page(embedding url: URL) -> String {
        let source = url.absoluteString.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>html, body { margin: 0; height: 100%; background: #000; overflow: hidden } iframe { border: 0; width: 100%; height: 100% }</style>
        </head><body>
        <iframe src="\(source)" referrerpolicy="strict-origin-when-cross-origin"
                allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
        </body></html>
        """
    }
}

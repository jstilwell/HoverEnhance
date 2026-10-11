import WebKit

/// Plays embeds in a web view. The most recent one stays alive, paused, after its preview closes,
/// so hovering the same link again picks up where it left off. Links clicked in a player, such as
/// its title or "Watch on YouTube", open in the browser.
@MainActor
final class EmbedPlayer: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var current: (embed: Embed, view: WKWebView)?

    func view(for embed: Embed) -> WKWebView? {
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

    /// A link that leaves the player, for the page around it or a new window, opens in the browser.
    /// Links within the player's own frame stay there.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame != false else { return .allow }
        openInBrowser(navigationAction)
        return .cancel
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

    /// Pauses the current embed without losing its place.
    func suspend() {
        current?.view.setAllMediaPlaybackSuspended(true)
    }

    private func discard() {
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

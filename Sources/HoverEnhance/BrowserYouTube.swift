import AppKit

/// Subscribing through the user's own signed-in YouTube tab instead of the YouTube Data API: the
/// browser runs YouTube's internal web requests (the ones its Subscribe button sends) via AppleScript.
/// Easier to set up than an OAuth client, but YouTube can change those requests without notice.
enum BrowserYouTube {
    /// Browsers that can run JavaScript in a tab from AppleScript.
    enum Kind: Equatable {
        case chromium, safari

        init?(bundleID: String) {
            if bundleID == "com.apple.Safari" || bundleID == "com.apple.SafariTechnologyPreview" {
                self = .safari
                return
            }
            // Chromium browsers that keep Chrome's scripting dictionary: Chrome, Helium, Vivaldi, Brave, Edge, Arc…
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                  WebEngine(appAt: url) == .chromium,
                  Bundle(url: url)?.object(forInfoDictionaryKey: "OSAScriptingDefinition") != nil else { return nil }
            self = .chromium
        }
    }

    enum Failure: LocalizedError, Equatable {
        case unsupported(browser: String)
        case notRunning(browser: String)
        case automationDenied(browser: String)
        case javaScriptOff(browser: String, safari: Bool)
        case noYouTubeTab(browser: String)
        case signedOut(browser: String)
        case youtube(String)
        case timedOut
        case script(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let browser): "\(browser) can't run YouTube actions. Use the Google API in Settings → Accounts."
            case .notRunning(let browser): "\(browser) isn't open."
            case .automationDenied(let browser): "Allow HoverEnhance to control \(browser) in System Settings → Privacy & Security → Automation."
            case .javaScriptOff(let browser, let safari):
                safari ? "In Safari, turn on Develop → Allow JavaScript from Apple Events."
                       : "In \(browser), turn on View → Developer → Allow JavaScript from Apple Events."
            case .noYouTubeTab(let browser): "Open YouTube in \(browser)."
            case .signedOut(let browser): "Sign in to YouTube in \(browser)."
            case .youtube(let message): "YouTube didn't accept the request (\(message))."
            case .timedOut: "YouTube didn't answer in time."
            case .script(let message): message
            }
        }
    }

    // MARK: - Operations

    /// Whether the browser's signed-in account subscribes to `channelID`; nil if YouTube's answer
    /// doesn't say.
    static func isSubscribed(to channelID: String, in bundleID: String) async throws -> Bool? {
        try await perform(.status(channelID: channelID), in: bundleID).subscribed
    }

    static func setSubscribed(_ subscribed: Bool, to channelID: String, in bundleID: String) async throws {
        _ = try await perform(subscribed ? .subscribe(channelID: channelID) : .unsubscribe(channelID: channelID), in: bundleID)
    }

    /// For Settings: confirms scripting works and the browser is signed in to YouTube.
    static func check(_ bundleID: String) async throws {
        _ = try await perform(.check, in: bundleID)
    }

    // MARK: - Running

    enum Action: Equatable {
        case check
        case status(channelID: String)
        case subscribe(channelID: String)
        case unsubscribe(channelID: String)
    }

    struct Result: Equatable {
        var subscribed: Bool?
    }

    static func name(of bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private static func perform(_ action: Action, in bundleID: String) async throws -> Result {
        let browser = name(of: bundleID)
        guard let kind = Kind(bundleID: bundleID) else { throw Failure.unsupported(browser: browser) }
        let key = "__hoverEnhance_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")

        _ = try await runAppleScript(appleScript(running: startScript(action, key: key), in: bundleID, kind: kind), browser: browser, kind: kind)
        // The page does the work asynchronously; read its answer back.
        let poll = appleScript(running: "JSON.stringify(window[\(javaScriptLiteral(key))] || null)", in: bundleID, kind: kind)
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
            let output = try await runAppleScript(poll, browser: browser, kind: kind)
            if let result = try parse(output, browser: browser) { return result }
        }
        throw Failure.timedOut
    }

    /// The page's answer: nil while it's still working.
    static func parse(_ output: String, browser: String) throws -> Result? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              object["done"] as? Bool == true else { return nil }
        switch object["error"] as? String {
        case nil: return Result(subscribed: object["subscribed"] as? Bool)
        case "signed-out": throw Failure.signedOut(browser: browser)
        case "not-youtube": throw Failure.noYouTubeTab(browser: browser)
        case let message?: throw Failure.youtube(message)
        }
    }

    // MARK: - Scripts

    /// JavaScript that starts `action` in the YouTube page and leaves the outcome in `window[key]`.
    /// It authenticates the way YouTube's own web client does: a SAPISIDHASH header from the
    /// page's SAPISID cookie, plus the page's InnerTube context.
    static func startScript(_ action: Action, key: String) -> String {
        let work = switch action {
        case .check:
            "return {};"
        case .status(let id):
            """
            const text = await call("browse", { browseId: \(javaScriptLiteral(id)) });
            const found = text.match(/"subscribed"\\s*:\\s*(true|false)/) || text.match(/"isSubscribed"\\s*:\\s*(true|false)/);
            return { subscribed: found ? found[1] === "true" : null };
            """
        case .subscribe(let id):
            "await call(\"subscription/subscribe\", { channelIds: [\(javaScriptLiteral(id))] }); return { subscribed: true };"
        case .unsubscribe(let id):
            "await call(\"subscription/unsubscribe\", { channelIds: [\(javaScriptLiteral(id))] }); return { subscribed: false };"
        }
        return """
        (() => {
          const key = \(javaScriptLiteral(key));
          window[key] = { done: false };
          (async () => {
            const cfg = window.ytcfg;
            if (!cfg || !cfg.get) throw new Error("not-youtube");
            const cookie = document.cookie.match(/(?:^|;\\s*)(?:SAPISID|__Secure-3PAPISID)=([^;]+)/);
            if (!cookie) throw new Error("signed-out");
            const origin = location.origin;
            const time = Math.floor(Date.now() / 1000);
            const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(time + " " + cookie[1] + " " + origin));
            const hash = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
            const headers = {
              "Content-Type": "application/json",
              "Authorization": "SAPISIDHASH " + time + "_" + hash,
              "X-Origin": origin,
              "X-Goog-AuthUser": String(cfg.get("SESSION_INDEX") || 0),
              "X-Youtube-Client-Name": String(cfg.get("INNERTUBE_CONTEXT_CLIENT_NAME") || 1),
              "X-Youtube-Client-Version": String(cfg.get("INNERTUBE_CONTEXT_CLIENT_VERSION") || "")
            };
            const call = async (path, body) => {
              const response = await fetch("/youtubei/v1/" + path + "?prettyPrint=false", {
                method: "POST", credentials: "include", headers,
                body: JSON.stringify(Object.assign({ context: cfg.get("INNERTUBE_CONTEXT") }, body))
              });
              const text = await response.text();
              if (!response.ok) throw new Error("HTTP " + response.status);
              return text;
            };
            \(work)
          })().then(
            result => { window[key] = Object.assign({ done: true }, result); },
            error => { window[key] = { done: true, error: String((error && error.message) || error) }; }
          );
          return "started";
        })()
        """
    }

    /// AppleScript that runs `javaScript` in the browser's YouTube tab: the front window's tab if it
    /// shows YouTube, otherwise the first YouTube tab anywhere.
    static func appleScript(running javaScript: String, in bundleID: String, kind: Kind) -> String {
        let js = appleScriptLiteral(javaScript)
        let isYouTube = "starts with \"https://www.youtube.com/\""
        let body = switch kind {
        case .chromium:
            """
                repeat with w in windows
                    if URL of active tab of w \(isYouTube) then return execute active tab of w javascript \(js)
                end repeat
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t \(isYouTube) then return execute t javascript \(js)
                    end repeat
                end repeat
            """
        case .safari:
            """
                repeat with w in windows
                    try
                        if URL of current tab of w \(isYouTube) then return do JavaScript \(js) in current tab of w
                    end try
                end repeat
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            if URL of t \(isYouTube) then return do JavaScript \(js) in t
                        end repeat
                    end try
                end repeat
            """
        }
        return """
        if application id "\(bundleID)" is not running then error "not running" number 1002
        tell application id "\(bundleID)"
        \(body)
        end tell
        error "no YouTube tab" number 1001
        """
    }

    static func javaScriptLiteral(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [string])
        return data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }

    static func appleScriptLiteral(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// osascript reports errors like "execution error: Helium got an error: … (-1743)".
    static func failure(fromOsascript message: String, browser: String, kind: Kind) -> Failure {
        let number = message.firstMatch(of: /\((-?\d+)\)\s*$/).flatMap { Int($0.1) }
        switch number {
        case -1743: return .automationDenied(browser: browser)
        case 1001: return .noYouTubeTab(browser: browser)
        case 1002, -600: return .notRunning(browser: browser)
        default: break
        }
        if message.contains("JavaScript"), message.contains("turned off") || message.contains("Allow JavaScript from Apple Events") {
            return .javaScriptOff(browser: browser, safari: kind == .safari)
        }
        return .script(message.replacingOccurrences(of: "execution error: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Runs AppleScript in osascript, so a permission prompt or a slow page never blocks the app.
    /// macOS asks for Automation permission on HoverEnhance's behalf, as the process that started it.
    private static func runAppleScript(_ source: String, browser: String, kind: Kind) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]
                let output = Pipe(), errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let out = output.fileHandleForReading.readDataToEndOfFile()
                let err = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: failure(fromOsascript: String(decoding: err, as: UTF8.self), browser: browser, kind: kind))
                }
            }
        }
    }
}

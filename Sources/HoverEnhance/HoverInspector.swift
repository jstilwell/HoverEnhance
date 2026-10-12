import AppKit
import ApplicationServices

enum InspectionError: Error, Equatable {
    case notTrusted
    case nothingUnderCursor
    case appNotResponding
    /// The cursor is over one of our own windows (e.g. the HUD).
    case ownWindow
    /// The cursor moved on before the look was done, so it wasn't finished.
    case superseded
    case failed(code: Int32)

    init(_ error: AXError) {
        switch error {
        case .apiDisabled: self = .notTrusted
        case .noValue, .success: self = .nothingUnderCursor
        case .cannotComplete: self = .appNotResponding
        default: self = .failed(code: error.rawValue)
        }
    }

    var message: String {
        switch self {
        case .notTrusted: "Accessibility access is off.\nMenu bar icon → Grant Accessibility Access…"
        case .nothingUnderCursor: "Nothing accessible under the cursor."
        case .appNotResponding: "The app under the cursor didn't respond in time."
        case .ownWindow: "(HoverEnhance)"
        case .superseded: "(Moved on)"
        case .failed(let code): "Accessibility error \(code)."
        }
    }
}

/// What the settings ask of the inspector, as plain values it can take to its queue.
struct InspectionPolicy: Sendable, Equatable {
    /// Bundle IDs of apps previews skip: they get a bare result, without the walk through their tree.
    var skipped: Set<String> = []
    /// Whether apps other than browsers can show previews, and so are worth switching on (Electron apps).
    var includesOtherApps = true
}

/// Answers "what's under this point?" using the Accessibility API.
///
/// AX calls are synchronous IPC into the target app and stall when that app is busy, so they all
/// run on one private serial queue. Mutable state is confined to that queue.
final class HoverInspector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "HoverEnhance.inspector", qos: .userInitiated)
    private let systemWide = AXElement.systemWide()
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var preparedPIDs: Set<pid_t> = []
    /// Apps whose web trees this switched on, with the attribute it set, so it can switch them back off.
    /// Apps that had it on already, from VoiceOver or another tool, aren't listed: they're left as found.
    private var switchedOn: [pid_t: (bundleURL: URL, attribute: String)] = [:]

    init() {
        // Applies to every element we message: don't let a hung app block us for the default 6 seconds.
        systemWide.setMessagingTimeout(0.25)
    }

    /// `point` is in global display coordinates (top-left origin), as reported by `CGEvent`. `isWanted` is
    /// asked before each slow part: a look the cursor has since moved away from isn't finished.
    func inspect(at point: CGPoint, policy: InspectionPolicy = InspectionPolicy(),
                 isWanted: @escaping @Sendable () -> Bool = { true }) async -> Result<HoverInfo, InspectionError> {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.inspectNow(at: point, policy: policy, isWanted: isWanted)) }
        }
    }

    /// Asks Chromium and Electron apps to build their web-content accessibility tree, which they
    /// otherwise only do when they detect assistive technology.
    func prepare(pid: pid_t, policy: InspectionPolicy) {
        // Never this app: see `OwnWindows`.
        guard pid != ownPID else { return }
        queue.async { _ = self.prepareIfNeeded(pid: pid, policy: policy) }
    }

    /// Switches web trees back off in apps the policy no longer previews, or in every app it switched on
    /// when there's no policy (previews paused, or the app quitting). Left alone while VoiceOver runs,
    /// which needs them. `wait` waits for it, for when the app is about to quit.
    func switchOff(unlessKeptBy policy: InspectionPolicy?, voiceOverIsRunning: Bool, wait: Bool = false) {
        let work = { [self] in
            for (pid, record) in switchedOn {
                let app = NSRunningApplication(processIdentifier: pid)
                // A pid can be another app's by now.
                guard app?.bundleURL == record.bundleURL else {
                    switchedOn[pid] = nil
                    preparedPIDs.remove(pid)
                    continue
                }
                if let policy, let app, qualifies(app, policy: policy) { continue }
                if !voiceOverIsRunning { AXElement.application(pid: pid).set(record.attribute, to: kCFBooleanFalse) }
                switchedOn[pid] = nil
                preparedPIDs.remove(pid)
            }
        }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    private func inspectNow(at point: CGPoint, policy: InspectionPolicy, isWanted: () -> Bool) -> Result<HoverInfo, InspectionError> {
        guard isWanted() else { return .failure(.superseded) }
        let (hit, error) = systemWide.element(at: point)
        guard var element = hit else { return .failure(InspectionError(error)) }
        guard let pid = element.pid, pid != ownPID else { return .failure(.ownWindow) }
        // Enough to know the app is skipped, without walking its tree.
        if let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier, policy.skipped.contains(bundleID) {
            return .success(HoverInfo(pid: pid, appName: app.localizedName, bundleID: bundleID))
        }

        if prepareIfNeeded(pid: pid, policy: policy) {
            // The tree is built asynchronously, so the first hit-test was likely shallow. Look again.
            Thread.sleep(forTimeInterval: 0.3)
            if let retried = systemWide.element(at: point).0 { element = retried }
        }
        guard isWanted() else { return .failure(.superseded) }
        return .success(describe(element, pid: pid, at: point))
    }

    /// Whether previews could appear in `app`, so its web tree is worth having.
    private func qualifies(_ app: NSRunningApplication, policy: InspectionPolicy) -> Bool {
        guard let bundleURL = app.bundleURL, !policy.skipped.contains(app.bundleIdentifier ?? "") else { return false }
        return policy.includesOtherApps || AppKind.of(appAt: bundleURL) == .browser
    }

    /// Returns true if this call just switched the app's tree on.
    private func prepareIfNeeded(pid: pid_t, policy: InspectionPolicy) -> Bool {
        guard !preparedPIDs.contains(pid), let running = NSRunningApplication(processIdentifier: pid), qualifies(running, policy: policy),
              let bundleURL = running.bundleURL else { return false }
        preparedPIDs.insert(pid)
        guard let engine = WebEngine(appAt: bundleURL) else { return false }

        let app = AXElement.application(pid: pid)
        let attribute = switch engine {
        case .electron: "AXManualAccessibility"
        // What VoiceOver sets on launch. Chromium enables full web accessibility in response, two
        // seconds after the last change. It's the only switch Chrome listens to: it ignores
        // Electron's AXManualAccessibility. While it's on, AppKit animates window moves made
        // through accessibility, which window managers such as Rectangle work around.
        case .chromium: "AXEnhancedUserInterface"
        }
        if app.attribute(attribute) as? Bool == true { return false }
        let result = app.set(attribute, to: kCFBooleanTrue)
        if result == .success { switchedOn[pid] = (bundleURL, attribute) }
        // Without access nothing was switched on; try again once access is back.
        if result == .apiDisabled { preparedPIDs.remove(pid) }
        return true
    }

    private func describe(_ element: AXElement, pid: pid_t, at point: CGPoint) -> HoverInfo {
        let app = NSRunningApplication(processIdentifier: pid)
        var info = HoverInfo(pid: pid, appName: app?.localizedName, bundleID: app?.bundleIdentifier)
        info.appKind = app?.bundleURL.map(AppKind.of(appAt:)) ?? .other
        info.role = element.role
        info.subrole = element.subrole
        info.title = element.title
        info.label = element.label
        info.value = element.value.map { $0.count > 200 ? $0.prefix(200) + "…" : $0 }
        info.url = element.url
        info.frame = element.frame

        // Walk up to find the enclosing link and page, and past a frame's page to the tab's. The path is
        // handy while exploring.
        var webArea: AXElement?
        var node: AXElement? = element
        while let current = node, info.ancestry.count < 40 {
            let role = current.role ?? "?"
            info.ancestry.append(role)
            if role == kAXWindowRole { break }
            if role == "AXWebArea" {
                let url = current.url
                if webArea == nil {
                    info.pageURL = url
                    webArea = current
                }
                info.topPageURL = url
            } else if role == "AXLink", webArea == nil, info.linkURL == nil {
                info.linkURL = current.url
            }
            node = current.parent
        }

        var imageElement: AXElement?
        if element.role == kAXImageRole, let url = info.url {
            info.imageURL = url
            info.imageFrame = info.frame
            imageElement = element
        } else if info.pageURL != nil, let image = image(at: point, near: element) {
            info.imageURL = image.url
            info.imageFrame = image.frame
            imageElement = image.element
        }
        if info.pageURL != nil, info.linkURL != nil, info.imageURL == nil {
            info.isOnText = isText(at: point, element: element)
        }
        // Only worth the look where there'd be a preview of a link or an image.
        if info.pageURL != nil, !info.isOnText, info.linkURL != nil || info.imageURL != nil {
            info.videoFrame = video(at: point, near: element)
        }
        // A photo outside any link, as in Instagram's feed: the post it's from, which may hold more.
        if info.linkURL == nil, info.videoFrame == nil, let webArea, let image = imageElement, let frame = info.imageFrame,
           let site = info.pageURL?.host().flatMap(MediaSite.init(host:)) {
            (info.postURL, info.postSearch) = postLink(before: image, frame: frame, in: webArea, site: site)
        }
        if info.bundleID == FinderItem.bundleID {
            info.fileURL = FinderItem.url(at: element)
            // The desktop is Finder's too, but isn't in a window.
            info.fileIsOnDesktop = info.fileURL != nil && !info.ancestry.contains(kAXWindowRole)
            if info.fileURL != nil {
                let finder = AXElement.application(pid: pid)
                let focused = finder.focusedElement
                info.finderIsBusy = FinderItem.isBusy(focusedRole: focused?.role, focusedSubrole: focused?.subrole,
                                                      windowSubroles: finder.windows.map(\.subrole))
            }
        }
        return info
    }

    /// Whether the point is on text. Chromium hit-tests to the text itself; WebKit stops at the link
    /// around it, so look for the text run under the point among a few descendants.
    private func isText(at point: CGPoint, element: AXElement) -> Bool {
        if element.role == "AXStaticText" { return true }
        var budget = 24
        var queue = element.children
        while !queue.isEmpty, budget > 0 {
            let node = queue.removeFirst()
            budget -= 1
            guard let frame = node.frame, frame.contains(point) else { continue }
            if node.role == "AXStaticText" { return true }
            queue.append(contentsOf: node.children)
        }
        return false
    }

    /// Sites often cover images with transparent links or buttons, so the hit element isn't the image.
    /// Look for one under the point among the descendants of the element, its parent, and its
    /// grandparent. Each node costs a few AX round-trips, so the search is capped.
    private func image(at point: CGPoint, near element: AXElement) -> (element: AXElement, url: URL, frame: CGRect)? {
        var budget = 40
        var searched: AXElement?
        var root: AXElement? = element
        for _ in 0..<3 {
            guard let current = root, current.role != "AXWebArea" else { return nil }
            var queue = [current]
            while !queue.isEmpty, budget > 0 {
                for child in queue.removeFirst().children {
                    if let searched, CFEqual(child.ref, searched.ref) { continue }
                    budget -= 1
                    guard budget > 0 else { break }
                    guard let frame = child.frame, frame.contains(point) else { continue }
                    if child.role == kAXImageRole, let url = child.url { return (child, url, frame) }
                    queue.append(child)
                }
            }
            searched = current
            root = current.parent
        }
        return nil
    }

    /// The link to the post a photo is from: the nearest before it in the page that leads to a post on
    /// the page's site, as the time in a post's header does, just above its photos. It must be close
    /// above the photo and across from it, or it's another post's.
    /// Also returns what it passed over, for the inspector.
    private func postLink(before image: AXElement, frame: CGRect, in webArea: AXElement, site: MediaSite) -> (URL?, String) {
        var passed: [String] = []
        for link in webArea.search("AXLinkSearchKey", limit: 8, from: image, backward: true) {
            guard let url = link.url else { continue }
            guard let source = SiteLinks.source(forLink: url), source.isPost, source.site == site else {
                passed.append(url.path())
                continue
            }
            guard let linkFrame = link.frame, linkFrame.maxY <= frame.minY + 1, frame.minY - linkFrame.maxY < 400,
                  linkFrame.maxX > frame.minX, linkFrame.minX < frame.maxX else {
                let at = link.frame.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height))" } ?? "nowhere"
                let photo = "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height))"
                return (nil, (passed + ["\(url.path()) at \(at), not just above the photo at \(photo)"]).joined(separator: " · "))
            }
            return (url, passed.joined(separator: " · "))
        }
        return (nil, passed.isEmpty ? "no links before the photo" : (passed + ["no post link"]).joined(separator: " · "))
    }

    /// The frame of a video the page shows under the point. Sites cover videos with their controls as
    /// they do images, so look among the element, its parent, and its grandparent. Chromium shows a
    /// video as a plain group, told apart only by its search for graphics (images and videos); WebKit
    /// gives it the video's URL, and the AXVideo subrole when it has controls. The search is capped.
    private func video(at point: CGPoint, near element: AXElement) -> CGRect? {
        var budget = 24
        var root: AXElement? = element
        for _ in 0..<3 {
            guard let current = root, current.role != "AXWebArea" else { return nil }
            for graphic in current.search("AXGraphicSearchKey", limit: 8) where budget > 0 {
                budget -= 1
                if graphic.role == kAXGroupRole, let frame = graphic.frame, frame.contains(point) { return frame }
            }
            for node in [current] + current.children where budget > 0 {
                budget -= 1
                guard node.role == kAXGroupRole, let frame = node.frame, frame.contains(point) else { continue }
                if node.subrole == "AXVideo" || (node.subrole != "AXAudio" && node.url != nil) { return frame }
            }
            root = current.parent
        }
        return nil
    }
}

/// Engines that build their accessibility tree for web content only on request.
enum WebEngine {
    case chromium
    case electron

    init?(appAt bundleURL: URL) {
        let frameworks = bundleURL.appending(path: "Contents/Frameworks")
        let fileManager = FileManager.default
        func exists(_ path: String) -> Bool {
            fileManager.fileExists(atPath: frameworks.appending(path: path).path(percentEncoded: false))
        }

        if exists("Electron Framework.framework") {
            self = .electron
            return
        }
        // Chromium browsers (Chrome, Edge, Brave, Vivaldi, Arc, Helium, …) ship "<Name> Framework.framework/Helpers".
        let names = (try? fileManager.contentsOfDirectory(atPath: frameworks.path(percentEncoded: false))) ?? []
        if names.contains(where: { $0.hasSuffix(" Framework.framework") && exists("\($0)/Helpers") }) {
            self = .chromium
            return
        }
        return nil
    }
}

/// Whether one of this app's windows is in front at a point: the preview, its notch, a card, the HUD,
/// Settings, About, the welcome window, or a menu.
enum OwnWindows {
    /// Asks the window server, so it runs where AppKit expects: on the main thread.
    @MainActor
    static func areInFront(at point: CGPoint) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let clicked = NSWindow.windowNumber(at: NSPoint(x: point.x, y: screenTop - point.y), belowWindowWithWindowNumber: 0)
        return areInFront(at: point, windows: windows, clickedWindow: clicked == 0 ? nil : clicked,
                          ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// `windows` is a window list front to back, as `CGWindowListCopyWindowInfo` gives it, and
    /// `clickedWindow` the window a click at the point would reach. A window of this app counts if it's
    /// that window or in front of it: accessibility finds click-through windows (the notch, the HUD)
    /// too. Other apps' windows in front of the clicked one let clicks and accessibility through, like
    /// the Dock's invisible window over the whole screen. Without a clicked window, any window of this
    /// app at the point counts.
    static func areInFront(at point: CGPoint, windows: [[String: Any]], clickedWindow: Int?, ownPID: pid_t) -> Bool {
        for window in windows {
            guard let bounds = (window[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  bounds.contains(point) else { continue }
            if (window[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == ownPID { return true }
            if let clickedWindow, window[kCGWindowNumber as String] as? Int == clickedWindow { return false }
        }
        return false
    }
}

import AppKit
import ApplicationServices

enum InspectionError: Error, Equatable {
    case notTrusted
    case nothingUnderCursor
    case appNotResponding
    /// The cursor is over one of our own windows (e.g. the HUD).
    case ownWindow
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
        case .failed(let code): "Accessibility error \(code)."
        }
    }
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

    init() {
        // Applies to every element we message: don't let a hung app block us for the default 6 seconds.
        systemWide.setMessagingTimeout(0.25)
    }

    /// `point` is in global display coordinates (top-left origin), as reported by `CGEvent`.
    func inspect(at point: CGPoint) async -> Result<HoverInfo, InspectionError> {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.inspectNow(at: point)) }
        }
    }

    /// Asks Chromium and Electron apps to build their web-content accessibility tree, which they
    /// otherwise only do when they detect assistive technology.
    func prepare(pid: pid_t) {
        queue.async { _ = self.prepareIfNeeded(pid: pid) }
    }

    private func inspectNow(at point: CGPoint) -> Result<HoverInfo, InspectionError> {
        let (hit, error) = systemWide.element(at: point)
        guard var element = hit else { return .failure(InspectionError(error)) }
        guard let pid = element.pid, pid != ownPID else { return .failure(.ownWindow) }

        if prepareIfNeeded(pid: pid) {
            // The tree is built asynchronously, so the first hit-test was likely shallow. Look again.
            Thread.sleep(forTimeInterval: 0.3)
            if let retried = systemWide.element(at: point).0 { element = retried }
        }
        return .success(describe(element, pid: pid, at: point))
    }

    /// Returns true if this call just switched the app's tree on.
    private func prepareIfNeeded(pid: pid_t) -> Bool {
        guard preparedPIDs.insert(pid).inserted,
              let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL,
              let engine = WebEngine(appAt: bundleURL) else { return false }

        let app = AXElement.application(pid: pid)
        switch engine {
        case .electron:
            app.set("AXManualAccessibility", to: kCFBooleanTrue)
        case .chromium:
            // What VoiceOver sets on launch. Chromium enables full web accessibility in response.
            app.set("AXEnhancedUserInterface", to: kCFBooleanTrue)
        }
        return true
    }

    private func describe(_ element: AXElement, pid: pid_t, at point: CGPoint) -> HoverInfo {
        let app = NSRunningApplication(processIdentifier: pid)
        var info = HoverInfo(pid: pid, appName: app?.localizedName, bundleID: app?.bundleIdentifier)
        info.role = element.role
        info.subrole = element.subrole
        info.title = element.title
        info.label = element.label
        info.value = element.value.map { $0.count > 200 ? $0.prefix(200) + "…" : $0 }
        info.url = element.url
        info.frame = element.frame

        // Walk up to find the enclosing link and page. The path is handy while exploring.
        var node: AXElement? = element
        while let current = node, info.ancestry.count < 40 {
            let role = current.role ?? "?"
            info.ancestry.append(role)
            if role == "AXLink", info.linkURL == nil { info.linkURL = current.url }
            if role == "AXWebArea" { info.pageURL = current.url; break }
            if role == kAXWindowRole { break }
            node = current.parent
        }

        if element.role == kAXImageRole, let url = info.url {
            info.imageURL = url
            info.imageFrame = info.frame
        } else if info.pageURL != nil, let image = image(at: point, near: element) {
            info.imageURL = image.url
            info.imageFrame = image.frame
        }
        return info
    }

    /// Sites often cover images with transparent links or buttons, so the hit element isn't the image.
    /// Look for one under the point among the descendants of the element, its parent, and its
    /// grandparent. Each node costs a few AX round-trips, so the search is capped.
    private func image(at point: CGPoint, near element: AXElement) -> (url: URL, frame: CGRect)? {
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
                    if child.role == kAXImageRole, let url = child.url { return (url, frame) }
                    queue.append(child)
                }
            }
            searched = current
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

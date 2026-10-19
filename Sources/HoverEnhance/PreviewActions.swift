import AppKit
import ImageIO
import UniformTypeIdentifiers

/// ⌘C and ⌘S, while a preview shows something they can copy or save.
enum PreviewShortcut: Sendable, Equatable {
    case copy, save

    /// Only ⌘ with C or S, by the character the key types, so other keyboard layouts work.
    init?(keyDown event: CGEvent) {
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard modifiers == .maskCommand, let key = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased() else { return nil }
        switch key {
        case "c": self = .copy
        case "s": self = .save
        default: return nil
        }
    }
}

/// While enabled, offers ⌘C and ⌘S to `handler`, which can act on them and swallow them, so the app under
/// the preview doesn't copy its selection or open a save dialog as well. It's enabled only while a preview
/// shows something to copy or save, and looks at no other key: every other one goes on as it came.
@MainActor
final class ShortcutTap {
    /// Return true to swallow the key press.
    var handler: ((PreviewShortcut, _ isRepeat: Bool) -> Bool)?
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { install() }
            if let port { CGEvent.tapEnable(tap: port, enable: isEnabled) }
        }
    }

    private var port: CFMachPort?

    private func install() {
        guard port == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<ShortcutTap>.fromOpaque(userInfo).takeUnretainedValue()
            // The tap's run loop source is on the main run loop.
            let swallow = MainActor.assumeIsolated { tap.shouldSwallow(type, event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("couldn't watch for copy and save shortcuts")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        self.port = port
    }

    private func shouldSwallow(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isEnabled, let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        guard isEnabled, type == .keyDown, let handler, let shortcut = PreviewShortcut(keyDown: event) else { return false }
        return handler(shortcut, event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
    }
}

/// Copying and saving what a preview shows.
enum PreviewActions {
    /// Puts an image file on the pasteboard as it came, with a TIFF beside it for apps that want one.
    @MainActor
    static func copy(image data: Data?, fallback: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let data, let type = imageType(of: data) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        if item.types.allSatisfy({ $0 != .tiff && $0 != .png }), let tiff = fallback.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
    }

    @MainActor
    static func copy(link url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    static func imageType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) else { return nil }
        return UTType(type as String)
    }

    static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// A name for a file saved from `url`: its own, made safe, with the extension its contents call for.
    /// "AbC123@jpeg" from Bluesky becomes "AbC123.jpg"; a name like "media" from Instagram stays.
    static func fileName(for url: URL, type: UTType?) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        name = String(name.unicodeScalars.filter { !CharacterSet(charactersIn: "/:\\").contains($0) && !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        if name.isEmpty { name = "Preview" }
        name = String(name.prefix(100))
        let own = url.pathExtension.lowercased()
        let ext: String? = if let type {
            // The address's own extension when it fits what's in the file, as "jpg" often does.
            UTType(filenameExtension: own)?.conforms(to: type) == true ? own : type == .jpeg ? "jpg" : type.preferredFilenameExtension
        } else {
            own.isEmpty ? nil : own
        }
        return ext.map { "\(name).\($0)" } ?? name
    }

    /// `name` in `folder`, or "name 2.ext", "name 3.ext"… if it's taken.
    static func unusedURL(for name: String, in folder: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }) -> URL {
        let first = folder.appending(path: name)
        guard exists(first) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for number in 2... {
            let candidate = folder.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            if !exists(candidate) { return candidate }
        }
        return first
    }

    /// Writes `data` to Downloads and records where it came from, as browsers do, for Finder's Get Info
    /// and HoverEnhance's file cards. Returns the file, or nil if it couldn't be written.
    static func save(_ data: Data, from url: URL, page: URL?, type: UTType?) -> URL? {
        let file = unusedURL(for: fileName(for: url, type: type), in: downloads)
        guard (try? data.write(to: file, options: .withoutOverwriting)) != nil else { return nil }
        finishDownload(file, from: url, page: page)
        return file
    }

    /// Moves a downloaded file into Downloads under a name like the original's.
    static func saveDownload(at temporary: URL, from url: URL, page: URL?, type: UTType?) -> URL? {
        let file = unusedURL(for: fileName(for: url, type: type), in: downloads)
        guard (try? FileManager.default.moveItem(at: temporary, to: file)) != nil else { return nil }
        finishDownload(file, from: url, page: page)
        return file
    }

    static func finishDownload(_ file: URL, from url: URL, page: URL?) {
        // Quarantined, as browsers' downloads are, so Gatekeeper checks the file before anything runs it.
        var quarantine: [String: Any] = [kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload, kLSQuarantineDataURLKey as String: url]
        if let page { quarantine[kLSQuarantineOriginURLKey as String] = page }
        var resource = file
        var values = URLResourceValues()
        values.quarantineProperties = quarantine
        try? resource.setResourceValues(values)
        let origins = [url.absoluteString] + (page.map { [$0.absoluteString] } ?? [])
        if let plist = try? PropertyListSerialization.data(fromPropertyList: origins, format: .binary, options: 0) {
            _ = plist.withUnsafeBytes { bytes in
                setxattr(file.path(percentEncoded: false), "com.apple.metadata:kMDItemWhereFroms", bytes.baseAddress, bytes.count, 0, 0)
            }
        }
        // Bounces the Downloads stack in the Dock, as browsers do when a download finishes.
        DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.DownloadFileFinished"),
                                                     object: file.path(percentEncoded: false))
    }

    /// Videos are downloaded without cookies, and may take a while.
    private static let videoSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30 * 60
        return URLSession(configuration: configuration)
    }()

    /// Downloads a video file into Downloads. Returns the file, or nil if it couldn't be downloaded.
    static func save(video url: URL, page: URL?) async -> URL? {
        var request = URLRequest(url: url)
        VideoPlayback.headers(for: url).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        guard let (temporary, response) = try? await videoSession.download(for: request, delegate: LocalRedirectGuard.shared) else { return nil }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return nil }
        return saveDownload(at: temporary, from: url, page: page, type: videoType(mimeType: response.mimeType, url: url))
    }

    /// A movie type for a saved video, from what the server said or the address, or MP4: never anything a
    /// double-click would run, whatever the address ends in.
    static func videoType(mimeType: String?, url: URL) -> UTType {
        let candidates = [mimeType.flatMap { UTType(mimeType: $0) }, UTType(filenameExtension: url.pathExtension)]
        return candidates.compactMap { $0 }.first { $0.conforms(to: .movie) } ?? .mpeg4Movie
    }

    /// Streams (HLS) come in pieces; only a single file can be saved.
    static func canSave(video url: URL) -> Bool {
        url.pathExtension.lowercased() != "m3u8"
    }
}

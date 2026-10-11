import AppKit
import QuickLookThumbnailing

/// What a file card shows about one file or folder.
@MainActor @Observable
final class FileCard {
    let url: URL
    let options: FileCardOptions
    let details: FileDetails
    let name: String
    let icon: NSImage
    /// As Finder's Copy as Pathname writes it: no trailing slash on folders.
    let path: String
    /// What was just copied (the path, or a row's label); it shows a checkmark for a moment.
    private(set) var copied: String?
    @ObservationIgnored private var copyGeneration = 0
    /// A Quick Look thumbnail, which replaces the icon once it's made.
    private(set) var thumbnail: NSImage?
    /// Who's using it; nil while looking.
    private(set) var users: [FileUser]?
    private(set) var userIcons: [pid_t: NSImage] = [:]
    private(set) var quitStates: [pid_t: QuitState] = [:]

    enum QuitState: Equatable {
        /// Clicked once; a second click quits.
        case confirming
        case quitting
        /// Asked to quit but still running, perhaps asking about unsaved changes. Force Quit is offered.
        case stillRunning
        case quit
        case failed
    }

    init(url: URL, details: FileDetails, options: FileCardOptions) {
        self.url = url
        self.details = details
        self.options = options
        path = Self.path(of: url)
        name = FileManager.default.displayName(atPath: path)
        icon = NSWorkspace.shared.icon(forFile: path)
    }

    nonisolated static func path(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    var formattedPath: String { options.pathStyle.format(path) }

    var kindAndSize: String {
        let size = details.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [details.kind, size].compactMap { $0 }.joined(separator: " · ")
    }

    var rows: [DetailRow] { details.rows(pathStyle: options.pathStyle) }

    static let pathID = "path"
    static let linkTargetID = "linkTarget"
    /// The icon or thumbnail's size, in points.
    static let imageSize: CGFloat = 52

    /// Folders and files Quick Look can't draw keep their icon.
    func loadThumbnail() async {
        guard options.shows(.thumbnail), thumbnail == nil else { return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: Self.imageSize, height: Self.imageSize),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    /// Where an alias or symbolic link points, written like the path.
    var formattedLinkTarget: String? {
        switch details.linkTarget {
        case .found(let path)?, .missing(let path?)?: options.pathStyle.format(path)
        default: nil
        }
    }

    func loadUsers() async {
        guard options.shows(.users), users == nil else { return }
        let found = await FileUsers.find(url)
        for user in found {
            userIcons[user.pid] = NSRunningApplication(processIdentifier: user.pid)?.icon
                ?? user.executable.map(NSWorkspace.shared.icon(forFile:))
        }
        users = found
    }

    /// Quit takes a second click to confirm; if the process is still running after it's asked to
    /// quit, the button offers Force Quit.
    func quitClicked(_ user: FileUser) {
        switch quitStates[user.pid] {
        case nil, .failed:
            quitStates[user.pid] = .confirming
            Task {
                try? await Task.sleep(for: .seconds(4))
                if quitStates[user.pid] == .confirming { quitStates[user.pid] = nil }
            }
        case .confirming:
            quit(user, force: false)
        case .stillRunning:
            quit(user, force: true)
        case .quitting, .quit:
            break
        }
    }

    private func quit(_ user: FileUser, force: Bool) {
        guard FileUsers.quit(user.pid, force: force) else {
            quitStates[user.pid] = .failed
            return
        }
        // Set before anything waits, so more clicks meanwhile do nothing.
        quitStates[user.pid] = .quitting
        Task { await waitForExit(of: user, force: force) }
    }

    /// Apps can take a moment, or stop to ask about unsaved changes.
    private func waitForExit(of user: FileUser, force: Bool) async {
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if !FileUsers.isRunning(user.pid) {
                quitStates[user.pid] = .quit
                return
            }
        }
        quitStates[user.pid] = force ? .failed : .stillRunning
    }

    /// Copies `text`; `id` marks what was copied, for the checkmark.
    func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = id
        copyGeneration += 1
        let generation = copyGeneration
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if generation == copyGeneration { copied = nil }
        }
    }
}

import Foundation

/// One thing a file card can show. Each has its own switch in Settings → Finder; a detail that's off
/// isn't read at all.
enum FileCardField: String, CaseIterable, Identifiable, Sendable {
    case thumbnail, kind, size
    case path, linkTarget
    case created, modified, opened
    case whereFrom, downloadedBy
    case tags, cloud
    case dimensions, duration, pages
    case users

    /// Sections of the card, and of its settings.
    enum Group: CaseIterable, Identifiable, Sendable {
        case card, path, dates, downloads, status, media, inUse

        var id: Self { self }

        var title: String {
            switch self {
            case .card: "Card"
            case .path: "Path"
            case .dates: "Dates"
            case .downloads: "Downloads"
            case .status: "Tags and iCloud"
            case .media: "Images, audio, and video"
            case .inUse: "In use"
            }
        }

        var fields: [FileCardField] { FileCardField.allCases.filter { $0.group == self } }
    }

    var id: Self { self }

    var group: Group {
        switch self {
        case .thumbnail, .kind, .size: .card
        case .path, .linkTarget: .path
        case .created, .modified, .opened: .dates
        case .whereFrom, .downloadedBy: .downloads
        case .tags, .cloud: .status
        case .dimensions, .duration, .pages: .media
        case .users: .inUse
        }
    }

    var name: String {
        switch self {
        case .thumbnail: "Thumbnail"
        case .kind: "Kind"
        case .size: "Size"
        case .path: "Path"
        case .linkTarget: "Where an alias points"
        case .created: "Created"
        case .modified: "Modified"
        case .opened: "Last opened"
        case .whereFrom: "Where it came from"
        case .downloadedBy: "Who downloaded it"
        case .tags: "Tags"
        case .cloud: "iCloud status"
        case .dimensions: "Dimensions"
        case .duration: "Length"
        case .pages: "Pages"
        case .users: "Apps using it"
        }
    }

    var detail: String? {
        switch self {
        case .thumbnail: "A preview of images, documents, and videos in place of the icon"
        case .kind: "Such as PNG image or Folder"
        case .size: "Not shown for folders, which would mean adding up everything in them"
        case .path: "Click it to copy it"
        case .linkTarget: "The original of an alias or symbolic link; click it to copy it"
        case .opened: "Only when it was opened after it last changed"
        case .whereFrom: "The website a download came from"
        case .downloadedBy: "The app that downloaded it, and when"
        case .tags: "Finder tags, with their colors"
        case .cloud: "Whether a file in iCloud is on this Mac, in the cloud only, or syncing"
        case .dimensions: "Of images and videos"
        case .duration: "Of audio and video"
        case .pages: "Of PDFs and other documents"
        case .users: "Apps with it open in a window, and processes holding it open or working in the folder"
        case .created, .modified: nil
        }
    }
}

/// What file cards show, and how they act; set in Settings → Finder.
struct FileCardOptions: Sendable, Equatable {
    var hidden: Set<FileCardField> = []
    var pathStyle = PathStyle.full
    var offersQuit = true
    /// Clicking a detail copies it.
    var copiesDetails = true

    func shows(_ field: FileCardField) -> Bool { !hidden.contains(field) }
}

extension PathStyle {
    /// `path` written this way. `home` is the folder `~` stands for.
    func format(_ path: String, home: String = NSHomeDirectory()) -> String {
        switch self {
        case .full: path
        case .tilde: path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        case .quoted: Self.shellQuoted(path)
        }
    }

    /// Single-quoted when it holds anything a shell would read specially; a quote inside becomes '\''.
    static func shellQuoted(_ path: String) -> String {
        guard path.isEmpty || path.unicodeScalars.contains(where: { !shellSafe.contains($0) }) else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static let shellSafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,:@")
}

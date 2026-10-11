import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Facts about a file or folder for its card. What the file doesn't have, or the card doesn't show,
/// is nil.
struct FileDetails: Sendable, Equatable {
    struct Dimensions: Sendable, Equatable {
        let width: Int
        let height: Int
    }

    var kind: String?
    /// Bytes. Nil for folders and packages, whose size would take a walk through everything in them.
    var size: Int64?
    var created: Date?
    var modified: Date?
    /// When it was last opened, as Spotlight recorded it.
    var opened: Date?
    var dimensions: Dimensions?
    /// Seconds of audio or video.
    var duration: Double?
    var pages: Int?
    /// The page a download came from, or the download's own URL.
    var whereFrom: URL?
    var download: Download?
    var tags: [Tag] = []
    var cloud: CloudStatus?
    var linkTarget: LinkTarget?

    /// Reads what `options` asks for. This touches the disk and Spotlight, so call it off the main thread.
    ///
    /// Spotlight comes first because it already knows dimensions, lengths, and where downloads came from
    /// without opening the file, which in Desktop, Documents, and Downloads would need the user's
    /// permission. Files it hasn't indexed are read directly.
    static func load(_ url: URL, options: FileCardOptions) -> FileDetails {
        var details = FileDetails()
        let values = try? url.resourceValues(forKeys: [
            .localizedTypeDescriptionKey, .contentTypeKey, .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey,
        ])
        if options.shows(.kind) { details.kind = values?.localizedTypeDescription }
        if options.shows(.size), values?.isDirectory != true { details.size = values?.fileSize.map(Int64.init) }
        if options.shows(.created) { details.created = values?.creationDate }
        if options.shows(.modified) { details.modified = values?.contentModificationDate }
        if options.shows(.linkTarget) { details.linkTarget = linkTarget(of: url) }
        if options.shows(.downloadedBy) { details.download = download(of: url) }
        if options.shows(.tags) { details.tags = tags(of: url) ?? [] }
        if options.shows(.cloud) { details.cloud = cloudStatus(of: url) }

        let spotlightFields: [FileCardField] = [.opened, .dimensions, .duration, .pages, .whereFrom]
        guard spotlightFields.contains(where: options.shows) else { return details }
        let spotlight = MDItemCreateWithURL(nil, url as CFURL)
        func attribute<Value>(_ name: CFString) -> Value? {
            spotlight.flatMap { MDItemCopyAttribute($0, name) as? Value }
        }
        if options.shows(.opened), let opened: Date = attribute(kMDItemLastUsedDate) {
            // Spotlight counts making a file as opening it; only a later open says something new.
            let latest = [values?.creationDate, values?.contentModificationDate].compactMap { $0 }.max() ?? .distantPast
            if opened.timeIntervalSince(latest) > 60 { details.opened = opened }
        }
        if options.shows(.dimensions) {
            if let width: Int = attribute(kMDItemPixelWidth), let height: Int = attribute(kMDItemPixelHeight), width > 0, height > 0 {
                details.dimensions = Dimensions(width: width, height: height)
            } else if values?.contentType?.conforms(to: .image) == true {
                details.dimensions = imageDimensions(of: url)
            }
        }
        if options.shows(.duration) {
            details.duration = attribute(kMDItemDurationSeconds).flatMap { (seconds: Double) in seconds > 0 ? seconds : nil }
        }
        if options.shows(.pages) { details.pages = attribute(kMDItemNumberOfPages) }
        if options.shows(.whereFrom) {
            details.whereFrom = source(fromWhereFroms: attribute(kMDItemWhereFroms) ?? whereFroms(attributeOf: url) ?? [])
        }
        return details
    }

    /// The card's lines for these details, in the order of `FileCardField`. Kind, size, and path are
    /// shown elsewhere on the card.
    func rows(pathStyle: PathStyle) -> [DetailRow] {
        var rows: [DetailRow] = []
        func add(_ field: FileCardField, _ label: String, _ text: String?, copy: String? = nil) {
            guard let text else { return }
            rows.append(DetailRow(field: field, label: label, value: .text(text), copyText: copy ?? text))
        }
        add(.created, "Created", created.map(Self.formatDate), copy: created.map(Self.formatFullDate))
        add(.modified, "Modified", modified.map(Self.formatDate), copy: modified.map(Self.formatFullDate))
        add(.opened, "Opened", opened.map(Self.formatDate), copy: opened.map(Self.formatFullDate))
        if let whereFrom {
            rows.append(DetailRow(field: .whereFrom, label: "From", value: .link(Self.formatSource(whereFrom), whereFrom),
                                  copyText: whereFrom.absoluteString))
        }
        if let download {
            add(.downloadedBy, "Downloaded", [download.agent, download.date.map(Self.formatDate)].compactMap { $0 }.joined(separator: " · "),
                copy: [download.agent, download.date.map(Self.formatFullDate)].compactMap { $0 }.joined(separator: ", "))
        }
        if !tags.isEmpty {
            rows.append(DetailRow(field: .tags, label: "Tags", value: .tags(tags), copyText: tags.map(\.name).joined(separator: ", ")))
        }
        add(.cloud, "iCloud", cloud?.label)
        add(.dimensions, "Dimensions", dimensions.map { "\($0.width) × \($0.height)" })
        add(.duration, "Length", duration.map(Self.formatDuration))
        add(.pages, "Pages", pages.map(String.init))
        return rows
    }

    /// Browsers record a download's own URL, then the page it was downloaded from; the page says more.
    /// Mail and Messages record addresses and subjects, which aren't web pages and are skipped.
    static func source(fromWhereFroms whereFroms: [String]) -> URL? {
        whereFroms.compactMap(URL.init(string:)).last { ["http", "https"].contains($0.scheme?.lowercased()) }
    }

    /// The list browsers write to a download, read from the file itself for when Spotlight hasn't indexed it.
    static func whereFroms(attributeOf url: URL) -> [String]? {
        attribute("com.apple.metadata:kMDItemWhereFroms", of: url)
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String] }
    }

    /// Reads only the image's header.
    static func imageDimensions(of url: URL) -> Dimensions? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return Dimensions(width: width, height: height)
    }

    // MARK: - Formatting

    /// "Today at 5:05 PM", "Oct 8, 2026 at 1:54 PM".
    static func formatDate(_ date: Date) -> String { relativeDateFormatter.string(from: date) }

    /// What a copied date says: the day in full, to the second, with no "Today".
    static func formatFullDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .standard)
    }

    private static let relativeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    /// "0:42", "2:31", "1:02:03".
    static func formatDuration(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        let (hours, minutes, rest) = (whole / 3600, whole / 60 % 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// "example.com/reports/2025", without the scheme or a leading "www.".
    static func formatSource(_ url: URL) -> String {
        var host = url.host() ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path(percentEncoded: false)
        return path.isEmpty || path == "/" ? host : host + path
    }
}

/// One line of a file card's details.
struct DetailRow: Sendable, Equatable, Identifiable {
    enum Value: Sendable, Equatable {
        case text(String)
        /// Text with an arrow that opens the URL.
        case link(String, URL)
        case tags([FileDetails.Tag])
        /// Still being looked up.
        case loading
    }

    let field: FileCardField
    let label: String
    let value: Value
    /// What clicking the row copies.
    let copyText: String?

    var id: String { label }
}

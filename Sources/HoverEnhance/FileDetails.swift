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
        if options.kindAndSize {
            details.kind = values?.localizedTypeDescription
            if values?.isDirectory != true { details.size = values?.fileSize.map(Int64.init) }
        }
        if options.dates {
            details.created = values?.creationDate
            details.modified = values?.contentModificationDate
        }
        guard options.dates || options.mediaInfo || options.whereFrom else { return details }

        let spotlight = MDItemCreateWithURL(nil, url as CFURL)
        func attribute<Value>(_ name: CFString) -> Value? {
            spotlight.flatMap { MDItemCopyAttribute($0, name) as? Value }
        }
        if options.dates, let opened: Date = attribute(kMDItemLastUsedDate) {
            // Spotlight counts making a file as opening it; only a later open says something new.
            let latest = [details.created, details.modified].compactMap { $0 }.max() ?? .distantPast
            if opened.timeIntervalSince(latest) > 60 { details.opened = opened }
        }
        if options.mediaInfo {
            if let width: Int = attribute(kMDItemPixelWidth), let height: Int = attribute(kMDItemPixelHeight), width > 0, height > 0 {
                details.dimensions = Dimensions(width: width, height: height)
            } else if values?.contentType?.conforms(to: .image) == true {
                details.dimensions = imageDimensions(of: url)
            }
            details.duration = attribute(kMDItemDurationSeconds).flatMap { (seconds: Double) in seconds > 0 ? seconds : nil }
            details.pages = attribute(kMDItemNumberOfPages)
        }
        if options.whereFrom {
            details.whereFrom = source(fromWhereFroms: attribute(kMDItemWhereFroms) ?? whereFroms(attributeOf: url) ?? [])
        }
        return details
    }

    /// Browsers record a download's own URL, then the page it was downloaded from; the page says more.
    /// Mail and Messages record addresses and subjects, which aren't web pages and are skipped.
    static func source(fromWhereFroms whereFroms: [String]) -> URL? {
        whereFroms.compactMap(URL.init(string:)).last { ["http", "https"].contains($0.scheme?.lowercased()) }
    }

    /// The list browsers write to a download, read from the file itself for when Spotlight hasn't indexed it.
    static func whereFroms(attributeOf url: URL) -> [String]? {
        let name = "com.apple.metadata:kMDItemWhereFroms"
        let path = url.path(percentEncoded: false)
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
        guard read == size else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
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

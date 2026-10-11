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
    /// "Apple iPhone 15 Pro".
    var camera: String?
    var lens: String?
    var exposure: Exposure?
    /// "H.264", "AAC".
    var codecs: [String] = []
    /// Kilobits per second, as Spotlight records it.
    var bitRate: Double?
    var artist: String?
    var album: String?
    var archive: ZipSummary?
    var app: AppBundleInfo?
    var git: GitRepository?

    /// A detail looked up after the card appears.
    enum Lookup<Value: Sendable & Equatable>: Sendable, Equatable {
        case loading
        case found(Value)
        /// It couldn't be found out; the row is left out.
        case failed
    }

    struct Exposure: Sendable, Equatable {
        var fNumber: Double?
        var seconds: Double?
        var iso: Int?
        /// Millimeters.
        var focalLength: Double?

        var isEmpty: Bool { fNumber == nil && seconds == nil && iso == nil && focalLength == nil }
    }

    /// Reads what `options` asks for. This touches the disk and Spotlight, so call it off the main thread.
    ///
    /// Spotlight comes first because it already knows dimensions, lengths, and where downloads came from
    /// without opening the file, which in Desktop, Documents, and Downloads would need the user's
    /// permission. Files it hasn't indexed are read directly.
    static func load(_ url: URL, options: FileCardOptions) -> FileDetails {
        var details = FileDetails()
        let values = try? url.resourceValues(forKeys: [
            .localizedTypeDescriptionKey, .contentTypeKey, .isDirectoryKey, .isPackageKey, .fileSizeKey, .creationDateKey,
            .contentModificationDateKey,
        ])
        if options.shows(.kind) { details.kind = values?.localizedTypeDescription }
        if options.shows(.size), values?.isDirectory != true { details.size = values?.fileSize.map(Int64.init) }
        if options.shows(.created) { details.created = values?.creationDate }
        if options.shows(.modified) { details.modified = values?.contentModificationDate }
        if options.shows(.linkTarget) { details.linkTarget = linkTarget(of: url) }
        if options.shows(.downloadedBy) { details.download = download(of: url) }
        if options.shows(.tags) { details.tags = tags(of: url) ?? [] }
        if options.shows(.cloud) { details.cloud = cloudStatus(of: url) }

        if options.shows(.archive), url.pathExtension.lowercased() == "zip" { details.archive = ZipSummary.read(url) }
        if values?.isPackage == true, [.appVersion, .bundleID, .architectures, .minimumSystem, .signature].contains(where: options.shows),
           var app = AppBundleInfo.read(url) {
            if !options.shows(.appVersion) { app.version = nil }
            if !options.shows(.bundleID) { app.bundleID = nil }
            if !options.shows(.architectures) { app.architectures = [] }
            if !options.shows(.minimumSystem) { app.minimumSystem = nil }
            details.app = app
        }
        if values?.isDirectory == true, values?.isPackage != true, options.shows(.gitBranch) || options.shows(.gitChanges) {
            details.git = GitRepository.read(url)
            if !options.shows(.gitBranch) { details.git?.head = nil; details.git?.remote = nil }
        }

        let spotlightFields: [FileCardField] = [.opened, .dimensions, .duration, .pages, .whereFrom, .camera, .exposure, .codecs, .music]
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
        var indexedDimensions: Dimensions?
        if let width: Int = attribute(kMDItemPixelWidth), let height: Int = attribute(kMDItemPixelHeight), width > 0, height > 0 {
            indexedDimensions = Dimensions(width: width, height: height)
        }
        if options.shows(.dimensions) { details.dimensions = indexedDimensions }
        if options.shows(.camera) {
            details.camera = cameraName(make: attribute(kMDItemAcquisitionMake), model: attribute(kMDItemAcquisitionModel))
            details.lens = attribute("kMDItemLensModel" as CFString)
        }
        if options.shows(.exposure) {
            let exposure = Exposure(fNumber: attribute(kMDItemFNumber), seconds: attribute(kMDItemExposureTimeSeconds),
                                    iso: attribute(kMDItemISOSpeed), focalLength: attribute(kMDItemFocalLength))
            details.exposure = exposure.isEmpty ? nil : exposure
        }
        // An image Spotlight hasn't indexed: read its header once for all three. Indexed images always
        // have dimensions, so screenshots, which have no camera, aren't opened for nothing.
        if indexedDimensions == nil, values?.contentType?.conforms(to: .image) == true,
           [.dimensions, .camera, .exposure].contains(where: options.shows) {
            details.fillIn(fromImageAt: url, options: options)
        }
        if options.shows(.codecs) {
            details.codecs = attribute(kMDItemCodecs) ?? []
            let total: Double? = attribute(kMDItemTotalBitRate)
            let parts = [attribute(kMDItemVideoBitRate), attribute(kMDItemAudioBitRate)].compactMap { $0 as Double? }
            details.bitRate = total ?? (parts.isEmpty ? nil : parts.reduce(0, +))
        }
        if options.shows(.music), values?.contentType?.conforms(to: .audio) == true {
            details.artist = (attribute(kMDItemAuthors) as [String]?).map { $0.joined(separator: ", ") }
            details.album = attribute(kMDItemAlbum)
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
    /// shown elsewhere on the card; `signature` and `changes` are looked up after it appears.
    func rows(pathStyle: PathStyle, signature: Lookup<String>? = nil, changes: Lookup<Int>? = nil) -> [DetailRow] {
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
        add(.camera, "Camera", camera)
        add(.camera, "Lens", lens)
        add(.exposure, "Exposure", exposure.map(Self.formatExposure))
        let encoding = [codecs.isEmpty ? nil : codecs.joined(separator: ", "), bitRate.map(Self.formatBitRate)].compactMap { $0 }
        add(.codecs, "Codecs", encoding.isEmpty ? nil : encoding.joined(separator: " · "))
        add(.music, "Artist", artist)
        add(.music, "Album", album)
        add(.archive, "Contents", archive?.label)
        func addLookup<Value>(_ field: FileCardField, _ label: String, _ lookup: Lookup<Value>?, _ text: (Value) -> String) {
            switch lookup {
            case .loading?: rows.append(DetailRow(field: field, label: label, value: .loading, copyText: nil))
            case .found(let value)?: add(field, label, text(value))
            case .failed?, nil: break
            }
        }
        if let app {
            add(.appVersion, "Version", app.version)
            add(.bundleID, "Bundle ID", app.bundleID)
            add(.architectures, "Built for", app.architectures.isEmpty ? nil : app.architectures.joined(separator: " and "))
            add(.minimumSystem, "Requires", app.minimumSystem)
        }
        addLookup(.signature, "Signed by", signature) { $0 }
        if let git {
            switch git.head {
            case .branch(let name)?: add(.gitBranch, "Branch", name)
            case .detached(let commit)?: add(.gitBranch, "Branch", "Detached at \(commit)", copy: commit)
            case nil: break
            }
            if let remote = git.remote {
                let shown = GitRepository.displayRemote(remote)
                let value: DetailRow.Value = GitRepository.webPage(of: remote).map { .link(shown, $0) } ?? .text(shown)
                rows.append(DetailRow(field: .gitBranch, label: "Remote", value: value, copyText: remote))
            }
        }
        addLookup(.gitChanges, "Changes", changes) { count in
            count == 0 ? "None" : "\(count) uncommitted change\(count == 1 ? "" : "s")"
        }
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

    /// Dimensions, camera, and exposure from the image's header, for what Spotlight didn't have.
    mutating func fillIn(fromImageAt url: URL, options: FileCardOptions) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        if options.shows(.dimensions), dimensions == nil,
           let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            dimensions = Dimensions(width: width, height: height)
        }
        if options.shows(.camera) {
            camera = camera ?? Self.cameraName(make: tiff[kCGImagePropertyTIFFMake] as? String, model: tiff[kCGImagePropertyTIFFModel] as? String)
            lens = lens ?? exif[kCGImagePropertyExifLensModel] as? String
        }
        if options.shows(.exposure), exposure == nil {
            let read = Exposure(fNumber: exif[kCGImagePropertyExifFNumber] as? Double, seconds: exif[kCGImagePropertyExifExposureTime] as? Double,
                                iso: (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first,
                                focalLength: exif[kCGImagePropertyExifFocalLength] as? Double)
            exposure = read.isEmpty ? nil : read
        }
    }

    /// Cameras often repeat their maker in the model ("Canon" and "Canon EOS R5"); say it once.
    static func cameraName(make: String?, model: String?) -> String? {
        let make = make?.trimmingCharacters(in: .whitespaces), model = model?.trimmingCharacters(in: .whitespaces)
        guard let model, !model.isEmpty else { return make?.isEmpty == false ? make : nil }
        guard let make, !make.isEmpty,
              let brand = make.split(separator: " ").first, !model.lowercased().hasPrefix(brand.lowercased()) else { return model }
        return make + " " + model
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

    /// "ƒ/1.8 · 1/120 s · ISO 50 · 26 mm", as photographers write it.
    static func formatExposure(_ exposure: Exposure) -> String {
        func number(_ value: Double) -> String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        }
        let shutter = exposure.seconds.map { $0 < 1 ? "1/\(Int((1 / $0).rounded())) s" : "\(number($0)) s" }
        return [exposure.fNumber.map { "ƒ/" + number($0) }, shutter, exposure.iso.map { "ISO \($0)" },
                exposure.focalLength.map { "\(Int($0.rounded())) mm" }].compactMap { $0 }.joined(separator: " · ")
    }

    /// "658 kbps", "4.2 Mbps".
    static func formatBitRate(_ kilobits: Double) -> String {
        kilobits < 1000 ? "\(Int(kilobits.rounded())) kbps" : String(format: "%.1f Mbps", kilobits / 1000)
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

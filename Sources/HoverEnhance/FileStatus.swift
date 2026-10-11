import CoreServices
import Foundation

/// Facts macOS keeps about a file outside its contents: tags, cloud sync, the quarantine record of a
/// download, and where an alias or symbolic link points.
extension FileDetails {
    struct Tag: Sendable, Equatable {
        let name: String
        /// Finder's label number: 0 none, 1 gray, 2 green, 3 purple, 4 blue, 5 yellow, 6 red, 7 orange.
        let color: Int
    }

    enum CloudStatus: Sendable, Equatable {
        case downloaded, notDownloaded, downloading, uploading, conflict

        var label: String {
            switch self {
            case .downloaded: "Downloaded"
            case .notDownloaded: "In the cloud only"
            case .downloading: "Downloading"
            case .uploading: "Uploading"
            case .conflict: "Has conflicting versions"
            }
        }
    }

    struct Download: Sendable, Equatable {
        /// The app that downloaded it, such as Safari.
        let agent: String?
        let date: Date?
    }

    enum LinkTarget: Sendable, Equatable {
        case found(String)
        /// The original is gone; the path is where it last was, when the alias remembers it.
        case missing(String?)
    }

    // MARK: - Reading

    /// Finder keeps each tag's color beside its name ("Work\n6") in this attribute. A symbolic link's
    /// own tags are read, not its original's.
    static func tags(of url: URL) -> [Tag]? {
        attribute("com.apple.metadata:_kMDItemUserTags", of: url)
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String] }
            .map(parseTags)
    }

    static func parseTags(_ list: [String]) -> [Tag] {
        list.compactMap { entry in
            let parts = entry.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return Tag(name: String(name), color: parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
        }
    }

    /// Whether a cloud-synced file (iCloud Drive, or Desktop and Documents in iCloud) is on this Mac.
    /// Nil for files that aren't synced.
    static func cloudStatus(of url: URL) -> CloudStatus? {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemIsUploadingKey, .ubiquitousItemHasUnresolvedConflictsKey,
        ])
        return cloudStatus(isSynced: values?.isUbiquitousItem, downloadStatus: values?.ubiquitousItemDownloadingStatus,
                           isDownloading: values?.ubiquitousItemIsDownloading, isUploading: values?.ubiquitousItemIsUploading,
                           hasConflicts: values?.ubiquitousItemHasUnresolvedConflicts)
    }

    /// What's happening outranks where it is: a conflict, then a transfer, then whether it's here.
    static func cloudStatus(isSynced: Bool?, downloadStatus: URLUbiquitousItemDownloadingStatus?, isDownloading: Bool?,
                            isUploading: Bool?, hasConflicts: Bool?) -> CloudStatus? {
        guard isSynced == true else { return nil }
        if hasConflicts == true { return .conflict }
        if isDownloading == true { return .downloading }
        if isUploading == true { return .uploading }
        switch downloadStatus {
        case .current?, .downloaded?: return .downloaded
        case .notDownloaded?: return .notDownloaded
        default: return nil
        }
    }

    /// From the quarantine record macOS adds to downloads, which Gatekeeper checks before opening them.
    static func download(of url: URL) -> Download? {
        guard let record = (try? url.resourceValues(forKeys: [.quarantinePropertiesKey]))?.quarantineProperties else { return nil }
        let agent = record[kLSQuarantineAgentNameKey as String] as? String
        let date = record[kLSQuarantineTimeStampKey as String] as? Date
        return agent == nil && date == nil ? nil : Download(agent: agent, date: date)
    }

    /// Where a symbolic link or Finder alias points. Nil for anything else.
    static func linkTarget(of url: URL) -> LinkTarget? {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
        if values?.isSymbolicLink == true {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false)) else {
                return .missing(nil)
            }
            // Relative links count from the folder holding the link. `standardized` only drops "." and
            // ".."; `standardizedFileURL` would also turn /private/tmp into /tmp.
            let target = URL(filePath: destination, relativeTo: url.deletingLastPathComponent()).absoluteURL.standardized
            let path = FileCard.path(of: target)
            return FileManager.default.fileExists(atPath: path) ? .found(path) : .missing(path)
        }
        guard values?.isAliasFile == true else { return nil }
        if let target = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) {
            return .found(FileCard.path(of: target))
        }
        // The alias still records where the original was.
        let remembered = (try? URL.bookmarkData(withContentsOf: url))
            .flatMap { URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: $0)?.path }
        return .missing(remembered)
    }

    /// An extended attribute's bytes.
    static func attribute(_ name: String, of url: URL) -> Data? {
        let path = url.path(percentEncoded: false)
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return read == size ? data : nil
    }
}

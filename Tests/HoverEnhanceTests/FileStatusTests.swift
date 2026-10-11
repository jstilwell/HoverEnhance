import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HoverEnhance

struct FileStatusTests {
    /// A fresh folder for one test; it's removed when the test ends.
    private final class Scratch {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString)", directoryHint: .isDirectory)

        init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: folder) }

        func file(_ name: String) throws -> URL {
            let url = folder.appending(path: name)
            try Data("hello".utf8).write(to: url)
            return url
        }

        func setAttribute(_ name: String, _ data: Data, on url: URL) {
            let result = data.withUnsafeBytes { setxattr(url.path(percentEncoded: false), name, $0.baseAddress, data.count, 0, 0) }
            #expect(result == 0)
        }
    }

    @Test func tagsKeepTheirColors() throws {
        let scratch = try Scratch()
        let url = try scratch.file("tagged.txt")
        let list = try PropertyListSerialization.data(fromPropertyList: ["Work\n6", "Ideas", "Blue\n4"], format: .binary, options: 0)
        scratch.setAttribute("com.apple.metadata:_kMDItemUserTags", list, on: url)

        let details = FileDetails.load(url, options: FileCardOptions())
        #expect(details.tags == [.init(name: "Work", color: 6), .init(name: "Ideas", color: 0), .init(name: "Blue", color: 4)])
        #expect(details.rows(pathStyle: .full).first { $0.field == .tags }?.copyText == "Work, Ideas, Blue")
        #expect(FileDetails.load(url, options: FileCardOptions(hidden: [.tags])).tags.isEmpty)
    }

    @Test func tagParsingSkipsEmptyEntries() {
        #expect(FileDetails.parseTags(["", "A\n", "B\nx", "C\n2"]) == [.init(name: "A", color: 0), .init(name: "B", color: 0), .init(name: "C", color: 2)])
    }

    @Test func downloadsRecordTheAppAndTime() throws {
        let scratch = try Scratch()
        let url = try scratch.file("installer.dmg")
        let time = 1_760_000_000
        scratch.setAttribute("com.apple.quarantine", Data("0083;\(String(time, radix: 16));TestBrowser;".utf8), on: url)

        let download = try #require(FileDetails.load(url, options: FileCardOptions()).download)
        #expect(download.agent == "TestBrowser")
        #expect(download.date == Date(timeIntervalSince1970: TimeInterval(time)))
        #expect(FileDetails.download(of: try scratch.file("plain.txt")) == nil)
    }

    @Test func cloudStatusPrefersWhatsHappening() {
        func status(_ download: URLUbiquitousItemDownloadingStatus?, downloading: Bool = false, uploading: Bool = false,
                    conflicts: Bool = false, synced: Bool = true) -> FileDetails.CloudStatus? {
            FileDetails.cloudStatus(isSynced: synced, downloadStatus: download, isDownloading: downloading, isUploading: uploading,
                                    hasConflicts: conflicts)
        }
        #expect(status(.current) == .downloaded)
        #expect(status(.downloaded) == .downloaded)
        #expect(status(.notDownloaded) == .notDownloaded)
        #expect(status(.notDownloaded, downloading: true) == .downloading)
        #expect(status(.current, uploading: true) == .uploading)
        #expect(status(.current, uploading: true, conflicts: true) == .conflict)
        #expect(status(.current, synced: false) == nil)
        #expect(FileDetails.cloudStatus(of: FileManager.default.temporaryDirectory) == nil)
    }

    @Test func symbolicLinksPointSomewhere() throws {
        let scratch = try Scratch()
        let target = try scratch.file("original.txt")
        let link = scratch.folder.appending(path: "link")
        try FileManager.default.createSymbolicLink(atPath: link.path(percentEncoded: false), withDestinationPath: "../\(scratch.folder.lastPathComponent)/original.txt")
        #expect(FileDetails.linkTarget(of: link) == .found(FileCard.path(of: target)))
        // A link has its own tags, or none, whatever its original has.
        let list = try PropertyListSerialization.data(fromPropertyList: ["Work\n6"], format: .binary, options: 0)
        scratch.setAttribute("com.apple.metadata:_kMDItemUserTags", list, on: target)
        #expect(FileDetails.load(link, options: FileCardOptions()).tags.isEmpty)

        let dangling = scratch.folder.appending(path: "dangling")
        try FileManager.default.createSymbolicLink(atPath: dangling.path(percentEncoded: false), withDestinationPath: "/nowhere/gone.txt")
        #expect(FileDetails.linkTarget(of: dangling) == .missing("/nowhere/gone.txt"))
        #expect(FileDetails.linkTarget(of: target) == nil)
    }

    @Test func aliasesPointSomewhereEvenWhenTheOriginalIsGone() throws {
        let scratch = try Scratch()
        let target = try scratch.file("original.txt")
        let alias = scratch.folder.appending(path: "original alias")
        try URL.writeBookmarkData(try target.bookmarkData(options: .suitableForBookmarkFile), to: alias)
        guard case .found(let found)? = FileDetails.linkTarget(of: alias) else {
            Issue.record("the alias should resolve to its original")
            return
        }
        #expect(URL(filePath: found).resolvingSymlinksInPath() == target.resolvingSymlinksInPath())

        try FileManager.default.removeItem(at: target)
        guard case .missing(let remembered)? = FileDetails.linkTarget(of: alias) else {
            Issue.record("a deleted original should read as missing")
            return
        }
        #expect(remembered.map { URL(filePath: $0).lastPathComponent } == "original.txt")
    }

    @MainActor
    @Test func imagesGetAThumbnail() async throws {
        let scratch = try Scratch()
        let url = scratch.folder.appending(path: "dot.png")
        let context = try #require(CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))

        let card = FileCard(url: url, details: FileDetails(), options: FileCardOptions())
        await card.loadThumbnail()
        #expect(card.thumbnail != nil)

        let plain = FileCard(url: url, details: FileDetails(), options: FileCardOptions(hidden: [.thumbnail]))
        await plain.loadThumbnail()
        #expect(plain.thumbnail == nil)
    }
}

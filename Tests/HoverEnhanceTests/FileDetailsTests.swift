import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HoverEnhance

struct FileDetailsTests {
    /// A fresh folder for one test; it's removed when the test ends.
    private final class Scratch {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString)", directoryHint: .isDirectory)

        init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: folder) }

        func file(_ name: String, contents: String = "hello") throws -> URL {
            let url = folder.appending(path: name)
            try Data(contents.utf8).write(to: url)
            return url
        }
    }

    @Test func filesHaveKindSizeAndDates() throws {
        let scratch = try Scratch()
        let url = try scratch.file("notes.txt", contents: "twelve bytes")
        let details = FileDetails.load(url, options: FileCardOptions())
        #expect(details.kind != nil)
        #expect(details.size == 12)
        #expect(details.created != nil)
        #expect(details.modified != nil)
        // Spotlight calls a new file opened when it was made, which isn't worth a line.
        #expect(details.opened == nil)
        #expect(details.dimensions == nil && details.duration == nil && details.whereFrom == nil)
    }

    @Test func foldersHaveNoSize() throws {
        let scratch = try Scratch()
        let details = FileDetails.load(scratch.folder, options: FileCardOptions())
        #expect(details.kind != nil)
        #expect(details.size == nil)
    }

    @Test func imagesHaveDimensions() throws {
        let scratch = try Scratch()
        let url = scratch.folder.appending(path: "dot.png")
        let context = try #require(CGContext(data: nil, width: 37, height: 21, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))

        #expect(FileDetails.load(url, options: FileCardOptions()).dimensions == FileDetails.Dimensions(width: 37, height: 21))
    }

    @Test func downloadsKnowWhereTheyCameFrom() throws {
        let scratch = try Scratch()
        let url = try scratch.file("report.zip")
        let list = try PropertyListSerialization.data(fromPropertyList: ["https://cdn.example.com/f/report.zip", "https://www.example.com/reports"],
                                                      format: .binary, options: 0)
        let written = list.withUnsafeBytes { setxattr(url.path(percentEncoded: false), "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, list.count, 0, 0) }
        #expect(written == 0)

        let details = FileDetails.load(url, options: FileCardOptions())
        #expect(details.whereFrom == URL(string: "https://www.example.com/reports"))
        #expect(FileDetails.load(url, options: FileCardOptions(whereFrom: false)).whereFrom == nil)
    }

    @Test func turnedOffDetailsAreLeftOut() throws {
        let scratch = try Scratch()
        let url = try scratch.file("notes.txt")
        let details = FileDetails.load(url, options: FileCardOptions(kindAndSize: false, dates: false, mediaInfo: false, whereFrom: false))
        #expect(details == FileDetails())
    }

    @Test func sourcesPreferThePageAndSkipMail() {
        #expect(FileDetails.source(fromWhereFroms: ["https://cdn.example.com/a.zip", "https://example.com/page"]) == URL(string: "https://example.com/page"))
        #expect(FileDetails.source(fromWhereFroms: ["https://example.com/a.zip"]) == URL(string: "https://example.com/a.zip"))
        #expect(FileDetails.source(fromWhereFroms: ["Jane <jane@example.com>", "Re: lunch", "message:%3C123@example.com%3E"]) == nil)
        #expect(FileDetails.source(fromWhereFroms: []) == nil)
    }

    @Test func formatting() {
        #expect(FileDetails.formatDuration(42) == "0:42")
        #expect(FileDetails.formatDuration(151.4) == "2:31")
        #expect(FileDetails.formatDuration(59.6) == "1:00")
        #expect(FileDetails.formatDuration(3723) == "1:02:03")
        #expect(FileDetails.formatSource(URL(string: "https://www.example.com/reports/2025")!) == "example.com/reports/2025")
        #expect(FileDetails.formatSource(URL(string: "https://example.com/")!) == "example.com")
    }
}

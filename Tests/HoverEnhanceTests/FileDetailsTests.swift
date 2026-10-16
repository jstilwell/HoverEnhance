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

    /// Runs `body` with a named pipe at `name` in `folder`, then opens and closes the pipe for writing, so
    /// a read `body` started anyway ends rather than holding up the tests.
    private func withNamedPipe(_ name: String, in folder: URL, _ body: @escaping @Sendable (URL) -> Void) throws {
        let pipe = folder.appending(path: name)
        #expect(mkfifo(pipe.path(percentEncoded: false), 0o600) == 0)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { body(pipe); done.signal() }
        let finished = done.wait(timeout: .now() + 5) == .success
        let writer = open(pipe.path(percentEncoded: false), O_WRONLY | O_NONBLOCK)
        if writer >= 0 { close(writer) }
        #expect(finished, "reading \(name) waited for a writer")
        if !finished { done.wait() }
    }

    @Test func namedPipesArentRead() throws {
        let scratch = try Scratch()
        try withNamedPipe("trap.zip", in: scratch.folder) { pipe in
            #expect(!FileDetails.isRegularFile(pipe))
            #expect(ZipSummary.read(pipe) == nil)
            _ = FileDetails.load(pipe, options: FileCardOptions())
        }
        try withNamedPipe("trap.png", in: scratch.folder) { pipe in
            #expect(LocalImage.load(pipe, maxPixelSize: 100) == nil && LocalImage.pixelSize(of: pipe) == nil)
        }
        let git = scratch.folder.appending(path: "repo/.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try withNamedPipe("HEAD", in: git) { _ in
            #expect(GitRepository.read(git.deletingLastPathComponent()) == GitRepository(head: nil, remote: nil))
        }
        // A link to a file is read as the file.
        let file = try scratch.file("real.txt")
        let link = scratch.folder.appending(path: "link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(FileDetails.isRegularFile(file) && FileDetails.isRegularFile(link) && !FileDetails.isRegularFile(scratch.folder))
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
        #expect(FileDetails.load(url, options: FileCardOptions(hidden: [.whereFrom])).whereFrom == nil)
        #expect(details.rows(pathStyle: .full).last == DetailRow(
            field: .whereFrom, label: "From", value: .link("example.com/reports", URL(string: "https://www.example.com/reports")!),
            copyText: "https://www.example.com/reports"))
    }

    @Test func turnedOffDetailsAreLeftOut() throws {
        let scratch = try Scratch()
        let url = try scratch.file("notes.txt")
        let details = FileDetails.load(url, options: FileCardOptions(hidden: Set(FileCardField.allCases)))
        // Only the file's type is read regardless, since it decides how the file is previewed.
        var expected = FileDetails()
        expected.contentType = details.contentType
        #expect(details == expected)
        #expect(details.rows(pathStyle: .full).isEmpty)

        let datesOnly = FileDetails.load(url, options: FileCardOptions(hidden: [.kind, .size]))
        #expect(datesOnly.kind == nil && datesOnly.size == nil && datesOnly.created != nil)
    }

    @Test func sourcesPreferThePageAndSkipMail() {
        #expect(FileDetails.source(fromWhereFroms: ["https://cdn.example.com/a.zip", "https://example.com/page"]) == URL(string: "https://example.com/page"))
        #expect(FileDetails.source(fromWhereFroms: ["https://example.com/a.zip"]) == URL(string: "https://example.com/a.zip"))
        #expect(FileDetails.source(fromWhereFroms: ["Jane <jane@example.com>", "Re: lunch", "message:%3C123@example.com%3E"]) == nil)
        #expect(FileDetails.source(fromWhereFroms: []) == nil)
    }

    @Test func rowsFollowTheFieldOrderAndCopyDatesInFull() {
        let created = Date(timeIntervalSince1970: 1_760_000_000)
        let details = FileDetails(created: created, dimensions: .init(width: 1920, height: 1080), pages: 12)
        let rows = details.rows(pathStyle: .full)
        #expect(rows.map(\.label) == ["Created", "Dimensions", "Pages"])
        #expect(rows[0].copyText == FileDetails.formatFullDate(created))
        // The row shows a short date; copying gives it in full, with seconds.
        #expect(rows[0].value == .text(FileDetails.formatDate(created)))
        #expect(rows[0].value != .text(FileDetails.formatFullDate(created)))
        #expect(rows[1].value == .text("1920 × 1080"))
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

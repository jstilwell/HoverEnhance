import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HoverEnhance

struct MediaDetailsTests {
    @Test func exposureReadsLikeAPhotographerWritesIt() {
        #expect(FileDetails.formatExposure(.init(fNumber: 1.8, seconds: 1.0 / 120, iso: 50, focalLength: 26.2)) == "ƒ/1.8 · 1/120 s · ISO 50 · 26 mm")
        #expect(FileDetails.formatExposure(.init(fNumber: 2, seconds: 2.5)) == "ƒ/2 · 2.5 s")
        #expect(FileDetails.formatExposure(.init(seconds: 30)) == "30 s")
    }

    @Test func camerasSayTheirMakerOnce() {
        #expect(FileDetails.cameraName(make: "Apple", model: "iPhone 15 Pro") == "Apple iPhone 15 Pro")
        #expect(FileDetails.cameraName(make: "Canon", model: "Canon EOS R5") == "Canon EOS R5")
        #expect(FileDetails.cameraName(make: "NIKON CORPORATION", model: "NIKON Z 6") == "NIKON Z 6")
        #expect(FileDetails.cameraName(make: "FUJIFILM", model: nil) == "FUJIFILM")
        #expect(FileDetails.cameraName(make: " ", model: "") == nil)
    }

    @Test func bitRates() {
        #expect(FileDetails.formatBitRate(658) == "658 kbps")
        #expect(FileDetails.formatBitRate(4_210) == "4.2 Mbps")
    }

    @Test func photosSpotlightHasntIndexedAreReadDirectly() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(CGContext(data: nil, width: 30, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro"],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifFNumber: 1.78, kCGImagePropertyExifExposureTime: 1.0 / 120,
                kCGImagePropertyExifISOSpeedRatings: [50], kCGImagePropertyExifFocalLength: 6.86,
                kCGImagePropertyExifLensModel: "iPhone 15 Pro back camera 6.86mm f/1.78",
            ],
        ]
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let details = FileDetails.load(url, options: FileCardOptions())
        #expect(details.dimensions == .init(width: 30, height: 20))
        #expect(details.camera == "Apple iPhone 15 Pro")
        #expect(details.lens == "iPhone 15 Pro back camera 6.86mm f/1.78")
        #expect(details.exposure.map(FileDetails.formatExposure) == "ƒ/1.8 · 1/120 s · ISO 50 · 7 mm")
        let labels = details.rows(pathStyle: .full).map(\.label)
        #expect(labels.suffix(4) == ["Dimensions", "Camera", "Lens", "Exposure"])

        let noCamera = FileDetails.load(url, options: FileCardOptions(hidden: [.camera, .exposure]))
        #expect(noCamera.camera == nil && noCamera.exposure == nil && noCamera.dimensions != nil)
    }
}

struct ZipSummaryTests {
    /// A folder of files zipped with the system's zip tool; it's removed when the test ends.
    private final class Archive {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        var zip: URL { folder.appending(path: "archive.zip") }

        init(_ files: [String: Int], arguments: [String] = []) throws {
            let content = folder.appending(path: "content", directoryHint: .isDirectory)
            for (path, size) in files {
                let url = content.appending(path: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 65, count: size).write(to: url)
            }
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/zip")
            process.currentDirectoryURL = content
            process.arguments = ["-q", "-r"] + arguments + [zip.path(percentEncoded: false), "."]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }

        deinit { try? FileManager.default.removeItem(at: folder) }
    }

    @Test func countsFilesFoldersAndUnpackedSize() throws {
        let archive = try Archive(["a.txt": 1000, "docs/b.txt": 2000, "docs/deep/c.txt": 3000])
        let summary = try #require(ZipSummary.read(archive.zip))
        #expect(summary == ZipSummary(files: 3, folders: 2, unpackedSize: 6000, isEncrypted: false))
        #expect(summary.label == "3 files in 2 folders · 6 KB unpacked")
    }

    @Test func skipsMacResourceForks() throws {
        let archive = try Archive(["photo.jpg": 10, "__MACOSX/._photo.jpg": 10])
        let summary = try #require(ZipSummary.read(archive.zip))
        #expect(summary.files == 1 && summary.folders == 0)
        #expect(summary.label == "1 file · 10 bytes unpacked")
    }

    @Test func noticesEncryption() throws {
        let archive = try Archive(["secret.txt": 100], arguments: ["-P", "hunter2"])
        #expect(try #require(ZipSummary.read(archive.zip)).isEncrypted)
    }

    @Test func readsZip64() throws {
        let archive = try Archive(["a.txt": 500, "b.txt": 700], arguments: ["-fz"])
        #expect(try #require(ZipSummary.read(archive.zip)) == ZipSummary(files: 2, folders: 0, unpackedSize: 1200, isEncrypted: false))
    }

    @Test func leavesHugeDirectoriesAlone() throws {
        let archive = try Archive(["a.txt": 1, "b.txt": 1, "c.txt": 1])
        let summary = try #require(ZipSummary.read(archive.zip, maximumDirectorySize: 10))
        #expect(summary.unpackedSize == nil)
        #expect(summary.label == "3 items")
    }

    @Test func damagedFilesGiveNothing() throws {
        let archive = try Archive(["a.txt": 5000])
        let data = try Data(contentsOf: archive.zip)
        let truncated = archive.folder.appending(path: "truncated.zip")
        try data.prefix(data.count - 30).write(to: truncated)
        #expect(ZipSummary.read(truncated) == nil)
        let notZip = archive.folder.appending(path: "not.zip")
        try Data("just text, not an archive at all".utf8).write(to: notZip)
        #expect(ZipSummary.read(notZip) == nil)
        #expect(FileDetails.load(archive.zip, options: FileCardOptions()).archive?.files == 1)
    }
}

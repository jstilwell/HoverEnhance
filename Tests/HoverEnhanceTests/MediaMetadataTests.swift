import AppKit
import AVFoundation
import Foundation
import Testing
@testable import HoverEnhance

struct MediaMetadataTests {
    private func fixture(_ name: String) throws -> URL {
        let parts = name.split(separator: ".")
        return try #require(Bundle.module.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: "Fixtures"))
    }

    @Test(arguments: ["tagged.mp3", "tagged.m4a"])
    func songTagsAreRead(_ name: String) async throws {
        let metadata = try #require(await MediaMetadata.read(try fixture(name)))
        #expect(metadata.title == "Example Song")
        #expect(metadata.artist == "Example Artist")
        #expect(metadata.album == "Example Album")
        #expect(metadata.albumArtist == "Example Album Artist")
        #expect(metadata.composer == "Example Composer")
        #expect(metadata.genre == "Ambient")
        #expect(metadata.year == "2024")
        #expect(metadata.track == "3 of 12")
        #expect(metadata.disc == "1 of 2")
        #expect(metadata.audio == "22.05 kHz mono")
        let artwork = try #require(metadata.artwork)
        #expect(NSImage(data: artwork)?.size == CGSize(width: 48, height: 48))
    }

    @Test func untaggedAudioStillHasItsFormat() async throws {
        let metadata = try #require(await MediaMetadata.read(try fixture("untagged.mp3")))
        #expect(metadata.title == nil && metadata.artist == nil && metadata.artwork == nil)
        #expect(metadata.audio == "22.05 kHz mono")
        #expect(abs((metadata.duration ?? 0) - 1) < 0.2)
    }

    @Test func videosSayWhenAndWithWhatTheyWereRecorded() async throws {
        let metadata = try #require(await MediaMetadata.read(try fixture("clip.mov")))
        #expect(metadata.title == "Example Clip")
        #expect(metadata.recorded == Date(timeIntervalSince1970: 1_714_979_289))
        #expect(metadata.device == "ExampleCam Model 1")
        #expect(metadata.frameRate == 24)
        #expect(!metadata.isHDR)
        #expect(metadata.hasVideo && metadata.pixelSize == CGSize(width: 64, height: 36))
        #expect(metadata.audio == "48 kHz stereo")
    }

    @Test func filesThatArentMediaGiveNothing() async throws {
        let text = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString).txt")
        try Data("not media".utf8).write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }
        #expect(await MediaMetadata.read(text) == nil)
    }

    @Test func positionsAndGenres() {
        #expect(MediaMetadata.position("3/12") == "3 of 12")
        #expect(MediaMetadata.position("7") == "7")
        #expect(MediaMetadata.position("0/12") == nil)
        #expect(MediaMetadata.position(Data([0, 0, 0, 3, 0, 12, 0, 0])) == "3 of 12")
        #expect(MediaMetadata.position(Data([0, 0, 0, 5, 0, 0])) == "5")
        #expect(MediaMetadata.genre("(13)") == nil)
        #expect(MediaMetadata.genre("(13)Pop") == "Pop")
        #expect(MediaMetadata.genre("Jazz") == "Jazz")
        #expect(MediaMetadata.audioDescription(sampleRate: 44100, channels: 6) == "44.1 kHz, 6 channels")
    }
}

struct MediaDetailsRowsTests {
    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    private func details(_ url: URL, hiding hidden: Set<FileCardField> = []) async -> FileDetails {
        let options = FileCardOptions(hidden: hidden)
        var details = FileDetails.load(url, options: options)
        await details.addMedia(from: url, options: options)
        return details
    }

    private func values(_ details: FileDetails) -> [String: String] {
        Dictionary(details.rows(pathStyle: .full).compactMap { row in
            if case .text(let text) = row.value { (row.label, text) } else { nil }
        }, uniquingKeysWith: { first, _ in first })
    }

    @Test func songsShowTheirTags() async throws {
        let rows = values(await details(try fixture("tagged", "mp3")))
        #expect(rows["Title"] == "Example Song")
        #expect(rows["Artist"] == "Example Artist")
        #expect(rows["Album artist"] == "Example Album Artist")
        #expect(rows["Genre"] == "Ambient")
        #expect(rows["Track"] == "3 of 12")
        #expect(rows["Disc"] == "1 of 2")
        #expect(rows["Audio"] == "22.05 kHz mono")
        #expect(rows["Recorded"] == nil)
    }

    @Test func videosShowHowTheyWereRecorded() async throws {
        let rows = values(await details(try fixture("clip", "mov")))
        #expect(rows["Title"] == "Example Clip")
        #expect(rows["Recorded with"] == "ExampleCam Model 1")
        #expect(rows["Recorded"] != nil)
        #expect(rows["Frame rate"] == "24 fps")
        #expect(rows["Audio"] == "48 kHz stereo")
        #expect(rows["Dimensions"] == "64 × 36")
        #expect(rows["Album"] == nil)
    }

    @Test func detailsThatAreOffAreLeftOut() async throws {
        let song = values(await details(try fixture("tagged", "mp3"), hiding: [.music, .mediaFormat]))
        #expect(song["Title"] == nil && song["Artist"] == nil && song["Audio"] == nil)
        let clip = values(await details(try fixture("clip", "mov"), hiding: [.recording, .dimensions]))
        #expect(clip["Title"] == nil && clip["Recorded with"] == nil)
        #expect(clip["Dimensions"] == nil)
        #expect(clip["Frame rate"] == "24 fps")
    }
}

struct FileMediaKindTests {
    private func kind(_ url: URL) async -> FileMediaKind? {
        let options = FileCardOptions()
        var details = FileDetails.load(url, options: options)
        await details.addMedia(from: url, options: options, forPreview: true)
        return FileMediaKind(details: details)
    }

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    @Test func audioAndVideoAreToldApartByTheirTracks() async throws {
        #expect(await kind(try fixture("tagged", "mp3")) == .audio)
        #expect(await kind(try fixture("tagged", "m4a")) == .audio)
        #expect(await kind(try fixture("clip", "mov")) == .video)
    }

    @Test func imagesAreImagesAndOtherFilesArentMedia() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(path: "photo.png")
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 200, bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                   bytesPerRow: 0, bitsPerPixel: 0))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: image)
        let text = folder.appending(path: "notes.txt")
        try Data("notes".utf8).write(to: text)

        #expect(await kind(image) == .image)
        #expect(await kind(text) == nil)
        #expect(LocalImage.pixelSize(of: image) == CGSize(width: 300, height: 200))
        let decoded = try #require(LocalImage.load(image, maxPixelSize: 150))
        #expect(decoded.size == CGSize(width: 150, height: 100))
    }
}

@MainActor
struct FinderMediaSettingsTests {
    @Test func largePreviewsAreOnAndAudioWaitsForItsButton() {
        let name = "HoverEnhanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.finderMediaPreviews)
        #expect(!settings.finderAutoplayAudio)
        settings.finderMediaPreviews = false
        settings.finderAutoplayAudio = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.finderMediaPreviews && reloaded.finderAutoplayAudio)
        reloaded.restoreFinderDefaults()
        #expect(reloaded.finderMediaPreviews && !reloaded.finderAutoplayAudio)
    }
}

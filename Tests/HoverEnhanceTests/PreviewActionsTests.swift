import AppKit
import Testing
import UniformTypeIdentifiers
@testable import HoverEnhance

struct PreviewShortcutTests {
    private func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    @Test func theDefaultsAreCommandCSAndShiftCommandS() {
        let shortcuts = PreviewShortcut.defaults
        #expect(PreviewShortcut.matching(key(8, "c", .command), in: shortcuts) == .copy)
        #expect(PreviewShortcut.matching(key(1, "s", .command), in: shortcuts) == .save)
        #expect(PreviewShortcut.matching(key(1, "S", [.command, .shift]), in: shortcuts) == .saveAs)
        #expect(PreviewShortcut.matching(key(8, "c", []), in: shortcuts) == nil)
        #expect(PreviewShortcut.matching(key(8, "c", [.command, .option]), in: shortcuts) == nil)
        #expect(PreviewShortcut.matching(key(9, "v", .command), in: shortcuts) == nil)
    }

    @Test func menusShowShortcutsACharacterStandsFor() {
        #expect(Shortcut(keyCode: 35, modifiers: [.control, .option], key: "P").menuKeyEquivalent == "p")
        #expect(Shortcut(keyCode: 96, modifiers: .command, key: "F5").menuKeyEquivalent == "")
    }

    @Test func lettersMatchByTheCharacterTheyType() {
        // On Dvorak, the key that types C isn't QWERTY's C key.
        #expect(PreviewShortcut.matching(key(34, "c", .command), in: PreviewShortcut.defaults) == .copy)
        #expect(PreviewShortcut.matching(key(8, "j", .command), in: PreviewShortcut.defaults) == nil)
        // Keys named by what they are, like F5, go by key code.
        let f5 = Shortcut(keyCode: 96, modifiers: .command, key: "F5")
        #expect(PreviewShortcut.matching(key(96, "\u{F708}", .command), in: [.save: f5]) == .save)
    }

    @Test func aShortcutTurnedOffMatchesNothing() {
        #expect(PreviewShortcut.matching(key(8, "c", .command), in: [.save: PreviewShortcut.defaults[.save]!]) == nil)
    }

    @Test func previewShortcutsTakeOneModifier() {
        #expect(Shortcut(event: key(8, "c", .command)) == nil)
        #expect(Shortcut(event: key(8, "c", .command), oneModifier: true) == PreviewShortcut.defaults[.copy])
        #expect(Shortcut(event: key(8, "c", .shift), oneModifier: true) == nil)
    }
}

struct SavingTests {
    @Test func fileNames() {
        #expect(PreviewActions.fileName(for: URL(string: "https://pbs.twimg.com/media/A1.jpg?name=orig")!, type: .jpeg) == "A1.jpg")
        #expect(PreviewActions.fileName(for: URL(string: "https://cdn.bsky.app/img/feed_fullsize/plain/did/bafkrei@jpeg")!, type: .jpeg) == "bafkrei.jpg")
        #expect(PreviewActions.fileName(for: URL(string: "https://www.instagram.com/p/AbC/media/?size=l")!, type: .jpeg) == "media.jpg")
        #expect(PreviewActions.fileName(for: URL(string: "https://media.redgifs.com/Name.mp4")!, type: .mpeg4Movie) == "Name.mp4")
        #expect(PreviewActions.fileName(for: URL(string: "https://example.com/")!, type: .png) == "Preview.png")
        #expect(PreviewActions.fileName(for: URL(string: "https://example.com/..hidden.png")!, type: .png) == "hidden.png")
        #expect(PreviewActions.fileName(for: URL(string: "https://example.com/clip")!, type: nil) == "clip")
        // An address that names the wrong type gets the right one.
        #expect(PreviewActions.fileName(for: URL(string: "https://example.com/photo.png")!, type: .webP) == "photo.webp")
    }

    @Test func takenNamesGetANumber() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["/tmp/x/A.jpg", "/tmp/x/A 2.jpg"]
        #expect(PreviewActions.unusedURL(for: "A.jpg", in: folder) { taken.contains($0.path(percentEncoded: false)) }.lastPathComponent == "A 3.jpg")
        #expect(PreviewActions.unusedURL(for: "B.jpg", in: folder) { taken.contains($0.path(percentEncoded: false)) }.lastPathComponent == "B.jpg")
    }

    @Test func savedVideosAreAlwaysMovies() {
        let url = URL(string: "https://example.com/clip.mov")!
        #expect(PreviewActions.videoType(mimeType: "video/mp4", url: url) == .mpeg4Movie)
        #expect(PreviewActions.videoType(mimeType: "application/octet-stream", url: url) == .quickTimeMovie)
        #expect(PreviewActions.videoType(mimeType: "text/plain", url: URL(string: "https://example.com/run.command")!) == .mpeg4Movie)
        #expect(PreviewActions.fileName(for: URL(string: "https://example.com/run.command")!, type: .mpeg4Movie) == "run.mp4")
    }

    @Test func saveAsReplacesTheFileChosen() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = URL(string: "https://example.com/a.png")!
        let first = PreviewActions.save(Data("1".utf8), from: source, page: nil, type: .png, to: .folder(folder))
        let second = PreviewActions.save(Data("2".utf8), from: source, page: nil, type: .png, to: .folder(folder))
        #expect(first?.lastPathComponent == "a.png")
        #expect(second?.lastPathComponent == "a 2.png")
        let chosen = folder.appending(path: "a.png")
        #expect(PreviewActions.save(Data("3".utf8), from: source, page: nil, type: .png, to: .file(chosen)) == chosen)
        #expect(try Data(contentsOf: chosen) == Data("3".utf8))
    }

    @Test func aDownloadReplacesTheChosenFileOnlyOnceItsThere() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = URL(string: "https://example.com/a.mp4")!
        let chosen = folder.appending(path: "a.mp4"), download = folder.appending(path: "download.tmp")
        try Data("old".utf8).write(to: chosen)

        // The download went missing: the file that was there stays.
        #expect(PreviewActions.saveDownload(at: download, from: source, page: nil, type: .mpeg4Movie, to: .file(chosen)) == nil)
        #expect(try Data(contentsOf: chosen) == Data("old".utf8))

        try Data("new".utf8).write(to: download)
        #expect(PreviewActions.saveDownload(at: download, from: source, page: nil, type: .mpeg4Movie, to: .file(chosen)) == chosen)
        #expect(try Data(contentsOf: chosen) == Data("new".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["a.mp4"], "nothing left beside it")

        try Data("first".utf8).write(to: download)
        let fresh = folder.appending(path: "b.mp4")
        #expect(PreviewActions.saveDownload(at: download, from: source, page: nil, type: .mpeg4Movie, to: .file(fresh)) == fresh)
        #expect(try Data(contentsOf: fresh) == Data("first".utf8))
    }

    @Test func streamsCantBeSaved() {
        #expect(!PreviewActions.canSave(video: URL(string: "https://v.redd.it/a/HLSPlaylist.m3u8")!))
        #expect(PreviewActions.canSave(video: URL(string: "https://media.redgifs.com/A.mp4")!))
    }

    @Test func imageTypesComeFromTheirContents() throws {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill(); image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        #expect(PreviewActions.imageType(of: png) == .png)
        #expect(PreviewActions.imageType(of: Data("not an image".utf8)) == nil)
    }
}

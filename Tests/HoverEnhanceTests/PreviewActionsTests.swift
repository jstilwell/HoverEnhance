import AppKit
import Testing
import UniformTypeIdentifiers
@testable import HoverEnhance

struct PreviewShortcutTests {
    private func key(_ code: CGKeyCode, _ character: String, flags: CGEventFlags) -> PreviewShortcut? {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        let utf16 = Array(character.utf16)
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        event.flags = flags
        return PreviewShortcut(keyDown: event)
    }

    @Test func onlyCommandCAndS() {
        #expect(key(8, "c", flags: .maskCommand) == .copy)
        #expect(key(1, "s", flags: .maskCommand) == .save)
        #expect(key(8, "c", flags: []) == nil)
        #expect(key(8, "c", flags: [.maskCommand, .maskShift]) == nil)
        #expect(key(1, "s", flags: [.maskCommand, .maskAlternate]) == nil)
        #expect(key(9, "v", flags: .maskCommand) == nil)
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

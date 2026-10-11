import Foundation
import Testing
@testable import HoverEnhance

struct PathStyleTests {
    private let home = "/Users/me"

    @Test func fullPathsStayAsTheyAre() {
        #expect(PathStyle.full.format("/Users/me/Downloads/a b.png", home: home) == "/Users/me/Downloads/a b.png")
    }

    @Test func tildeReplacesOnlyTheHomeFolder() {
        #expect(PathStyle.tilde.format("/Users/me/Downloads/a.png", home: home) == "~/Downloads/a.png")
        #expect(PathStyle.tilde.format("/Users/me", home: home) == "~")
        #expect(PathStyle.tilde.format("/Users/me2/a.png", home: home) == "/Users/me2/a.png")
        #expect(PathStyle.tilde.format("/Applications/Safari.app", home: home) == "/Applications/Safari.app")
    }

    @Test func quotingOnlyWhenTheShellNeedsIt() {
        #expect(PathStyle.quoted.format("/usr/local/bin/swift-format", home: home) == "/usr/local/bin/swift-format")
        #expect(PathStyle.quoted.format("/Users/me/My Files/a.txt", home: home) == "'/Users/me/My Files/a.txt'")
        #expect(PathStyle.quoted.format("/tmp/it's here", home: home) == #"'/tmp/it'\''s here'"#)
        #expect(PathStyle.quoted.format("/tmp/$HOME*", home: home) == "'/tmp/$HOME*'")
    }

    @Test func foldersLoseTheirTrailingSlash() {
        #expect(FileCard.path(of: URL(filePath: "/Users/me/Downloads/", directoryHint: .isDirectory)) == "/Users/me/Downloads")
        #expect(FileCard.path(of: URL(filePath: "/", directoryHint: .isDirectory)) == "/")
        #expect(FileCard.path(of: URL(filePath: "/tmp/é ñ.txt")) == "/tmp/é ñ.txt")
    }
}

struct FileSourceTests {
    @Test func finderItemsGetFileCards() {
        var info = HoverInfo(pid: 1, appName: "Finder", bundleID: FinderItem.bundleID)
        info.fileURL = URL(filePath: "/Applications/Safari.app")
        #expect(MediaResolver.source(for: info) == .file(URL(filePath: "/Applications/Safari.app")))
        #expect(MediaSource.file(URL(filePath: "/a")).site == nil)
    }

    @Test func fileCardsCanBeTurnedOff() {
        #expect(PreviewFilter().allows(.file(URL(filePath: "/a"))))
        #expect(!PreviewFilter(files: false).allows(.file(URL(filePath: "/a"))))
        #expect(PreviewFilter(files: false).apply(to: Media(items: [.file(URL(filePath: "/a"))])) == nil)
    }
}

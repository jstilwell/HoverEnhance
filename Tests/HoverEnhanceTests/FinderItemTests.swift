import Foundation
import Testing
@testable import HoverEnhance

/// A stand-in for Finder's accessibility tree, shaped like what Finder exposes in each view.
private final class Node: FinderNode {
    let role: String?
    let itemURL: URL?
    private(set) weak var parent: Node?
    private(set) var children: [Node] = []

    init(_ role: String?, item: String? = nil, _ children: [Node] = []) {
        self.role = role
        itemURL = item.map { URL(filePath: $0) }
        for child in children { child.parent = self }
        self.children = children
    }
}

struct FinderItemTests {
    private func url(_ node: Node) -> String? { FinderItem.url(at: node)?.path(percentEncoded: false) }

    @Test func listRowsLeadToTheNameCell() {
        let name = Node("AXTextField", item: "/Users/me/Downloads/eepy.png")
        let icon = Node("AXImage")
        let date = Node("AXStaticText")
        let size = Node("AXStaticText")
        let outline = Node("AXOutline", [
            Node("AXRow", [Node("AXCell", [icon, name]), Node("AXCell", [date]), Node("AXCell", [size])]),
            Node("AXRow", [Node("AXCell", [Node("AXImage"), Node("AXTextField", item: "/Users/me/Downloads/other.png")])]),
        ])
        _ = Node("AXScrollArea", [outline])
        #expect(url(name) == "/Users/me/Downloads/eepy.png")
        #expect(url(icon) == "/Users/me/Downloads/eepy.png")
        #expect(url(date) == "/Users/me/Downloads/eepy.png")
        #expect(url(size) == "/Users/me/Downloads/eepy.png")
    }

    @Test func iconsAndTheirLabelsLeadToTheItem() {
        let image = Node("AXImage", item: "/tmp/notes.txt")
        let group = Node("AXGroup", [image])
        let view = Node("AXList", [Node("AXList", [group, Node("AXGroup", [Node("AXImage", item: "/tmp/other.txt")])])])
        withExtendedLifetime(view) {
            #expect(url(image) == "/tmp/notes.txt")
            // The label area under the icon hit-tests to the item's group.
            #expect(url(group) == "/tmp/notes.txt")
        }
    }

    @Test func columnViewIconsLeadToTheName() {
        let icon = Node("AXImage")
        let column = Node("AXList", [Node("AXGroup", [icon, Node("AXTextField", item: "/Applications")])])
        withExtendedLifetime(column) {
            #expect(url(icon) == "/Applications")
        }
    }

    @Test func desktopSpaceAndStacksShowNothing() {
        let stack = Node("AXImage")
        let desktop = Node("AXGroup", [Node("AXImage", item: "/Users/me/Desktop/AppCleaner.app"), stack])
        let window = Node("AXScrollArea", [desktop])
        withExtendedLifetime(window) {
            // A stack has a file name but no URL, and empty desktop space hit-tests to the desktop's group.
            #expect(url(stack) == nil)
            #expect(url(desktop) == nil)
        }
    }

    @Test func containersAndSidebarRowsShowNothing() {
        let list = Node("AXList", [Node("AXGroup", [Node("AXImage", item: "/a")]), Node("AXGroup", [Node("AXImage", item: "/b")])])
        _ = Node("AXScrollArea", [list])
        #expect(url(list) == nil)

        let sidebarText = Node("AXStaticText")
        _ = Node("AXOutline", [Node("AXRow", [Node("AXCell", [sidebarText, Node("AXImage")])])])
        #expect(url(sidebarText) == nil)
    }

    @Test func quickLookAndRenamingKeepCardsAway() {
        // What Finder reported on macOS 27: Quick Look's panel is Finder's own window.
        #expect(FinderItem.isBusy(focusedRole: "AXWindow", focusedSubrole: "Quick Look", windowSubroles: ["AXStandardWindow", "Quick Look"]))
        #expect(FinderItem.isBusy(focusedRole: "AXOutline", focusedSubrole: nil, windowSubroles: ["AXStandardWindow", "AXQuickLook"]))
        // Renaming focuses a text field; searching focuses the search field, which doesn't count.
        #expect(FinderItem.isBusy(focusedRole: "AXTextField", focusedSubrole: nil, windowSubroles: ["AXStandardWindow"]))
        #expect(!FinderItem.isBusy(focusedRole: "AXTextField", focusedSubrole: "AXSearchField", windowSubroles: ["AXStandardWindow"]))
        #expect(!FinderItem.isBusy(focusedRole: "AXOutline", focusedSubrole: nil, windowSubroles: ["AXStandardWindow", nil]))
    }

    @Test func busyFinderGetsNoCard() {
        var info = HoverInfo(pid: 1, appName: "Finder", bundleID: FinderItem.bundleID)
        info.fileURL = URL(filePath: "/tmp/a.txt")
        info.finderIsBusy = true
        #expect(MediaResolver.source(for: info) == nil)
    }

    @Test func installerImagesGetNoCard() {
        #expect(FinderItem.isInstaller(readOnly: true, deviceModel: "Disk Image"))
        // A writable image kept for storage, and a read-only drive or share.
        #expect(!FinderItem.isInstaller(readOnly: false, deviceModel: "Disk Image"))
        #expect(!FinderItem.isInstaller(readOnly: true, deviceModel: "SSD"))
        #expect(!FinderItem.isInstaller(readOnly: true, deviceModel: nil))

        var info = HoverInfo(pid: 1, appName: "Finder", bundleID: FinderItem.bundleID)
        info.fileURL = URL(filePath: "/Volumes/Firefox/Firefox.app")
        info.fileIsInInstaller = true
        #expect(MediaResolver.source(for: info) == nil)
    }

    @Test func mountedImagesAreToldApart() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HoverEnhance-\(UUID().uuidString)")
        let content = folder.appending(path: "content")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: content.appending(path: "Applications"), withDestinationURL: URL(filePath: "/Applications"))
        try Data("hi".utf8).write(to: content.appending(path: "a.txt"))
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!FinderItem.isInInstaller(content.appending(path: "a.txt")))

        func hdiutil(_ arguments: String...) throws {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/hdiutil")
            process.arguments = arguments + ["-quiet"]
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0, "hdiutil \(arguments.joined(separator: " "))")
        }
        // An installer is compressed, so read-only; a writable image is kept for storage.
        for (format, isInstaller) in [("UDZO", true), ("UDRW", false)] {
            let image = folder.appending(path: "\(format).dmg").path(percentEncoded: false)
            let mount = folder.appending(path: "mount-\(format)")
            try hdiutil("create", "-volname", "HoverEnhance Test", "-srcfolder", content.path(percentEncoded: false), "-format", format, image)
            try hdiutil("attach", "-nobrowse", "-noverify", "-mountpoint", mount.path(percentEncoded: false), image)
            defer { try? hdiutil("detach", "-force", mount.path(percentEncoded: false)) }
            #expect(FinderItem.isInInstaller(mount.appending(path: "a.txt")) == isInstaller, "\(format)")
            #expect(FinderItem.isInInstaller(mount.appending(path: "Applications")) == isInstaller, "\(format)")
            // The image's own icon, as on the desktop.
            #expect(!FinderItem.isInInstaller(mount))
        }
    }

    @Test func fileReferenceURLsResolveToPaths() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "HoverEnhance-\(UUID().uuidString).txt")
        try Data("hi".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        // What Finder puts in AXURL.
        let reference = try #require(CFURLCreateFileReferenceURL(nil, file as CFURL, nil)?.takeRetainedValue())
        #expect((CFURLGetString(reference) as String).hasPrefix("file:///.file/id="))
        #expect(FinderItem.filePathURL(reference)?.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())

        #expect(FinderItem.filePathURL(URL(string: "nwnode://domain-Network")! as CFURL) == nil)
        #expect(FinderItem.filePathURL("file:///tmp" as CFString) == nil)
    }
}

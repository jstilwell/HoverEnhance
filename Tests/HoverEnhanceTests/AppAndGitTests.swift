import Foundation
import Testing
@testable import HoverEnhance

/// A fresh folder for one test; it's removed when the test ends.
private final class Scratch {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: folder) }

    @discardableResult
    func run(_ tool: String, _ arguments: [String], in directory: URL? = nil) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = directory ?? folder
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

struct AppBundleInfoTests {
    private let finder = URL(filePath: "/System/Library/CoreServices/Finder.app")

    @Test func systemAppsHaveVersionsAndArchitectures() throws {
        let info = try #require(AppBundleInfo.read(finder))
        #expect(info.bundleID == "com.apple.finder")
        #expect(info.version != nil)
        #expect(info.architectures.contains("Apple silicon"))
        #expect(AppBundleInfo.read(URL(filePath: "/System/Library/CoreServices", directoryHint: .isDirectory)) == nil)
    }

    @Test func signaturesSayWhoSigned() throws {
        #expect(AppBundleInfo.signature(of: finder) == "Apple")

        let scratch = try Scratch()
        let adHoc = scratch.folder.appending(path: "adhoc")
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: adHoc)
        #expect(try scratch.run("/usr/bin/codesign", ["--force", "--sign", "-", adHoc.path(percentEncoded: false)]) == 0)
        #expect(AppBundleInfo.signature(of: adHoc) == "Ad hoc, no developer")

        let unsigned = scratch.folder.appending(path: "unsigned")
        try FileManager.default.copyItem(at: adHoc, to: unsigned)
        #expect(try scratch.run("/usr/bin/codesign", ["--remove-signature", unsigned.path(percentEncoded: false)]) == 0)
        #expect(AppBundleInfo.signature(of: unsigned) == "Not signed")
    }

    @Test func signaturesCheckEveryFile() throws {
        let scratch = try Scratch()
        func app(_ name: String) throws -> URL {
            let app = scratch.folder.appending(path: "\(name).app", directoryHint: .isDirectory)
            let contents = app.appending(path: "Contents")
            try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: contents.appending(path: "Resources"), withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": "test.\(name)", "CFBundleExecutable": name]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appending(path: "Info.plist"))
            try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: contents.appending(path: "MacOS/\(name)"))
            try Data("as signed".utf8).write(to: contents.appending(path: "Resources/notes.txt"))
            #expect(try scratch.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path(percentEncoded: false)]) == 0)
            return app
        }
        #expect(AppBundleInfo.signature(of: try app("Intact")) == "Ad hoc, no developer")
        let changed = try app("Changed")
        try Data("changed".utf8).write(to: changed.appending(path: "Contents/Resources/notes.txt"))
        #expect(AppBundleInfo.signature(of: changed) == "Ad hoc, no developer · files changed since signing")
    }

    @Test func appRowsAndASignatureStillLoading() throws {
        var details = FileDetails()
        details.app = AppBundleInfo(version: "26.0 (21622)", bundleID: "com.apple.Safari", architectures: ["Apple silicon", "Intel"],
                                    minimumSystem: "macOS 26.0")
        let rows = details.rows(pathStyle: .full, signature: .loading)
        #expect(rows.map(\.label) == ["Version", "Bundle ID", "Built for", "Requires", "Signed by"])
        #expect(rows[2].value == .text("Apple silicon and Intel"))
        #expect(rows[4].value == .loading && rows[4].copyText == nil)
        #expect(details.rows(pathStyle: .full, signature: .failed).count == 4)
    }

    @Test func onlyWantedAppDetailsAreKept() {
        let details = FileDetails.load(finder, options: FileCardOptions(hidden: [.appVersion, .architectures]))
        #expect(details.app?.bundleID == "com.apple.finder")
        #expect(details.app?.version == nil && details.app?.architectures == [])
        #expect(FileDetails.load(finder, options: FileCardOptions(hidden: [.appVersion, .bundleID, .architectures, .minimumSystem, .signature])).app == nil)
    }
}

struct GitRepositoryTests {
    @Test func headsAreBranchesOrCommits() {
        #expect(GitRepository.parseHead("ref: refs/heads/feature/finder-file-cards\n") == .branch("feature/finder-file-cards"))
        #expect(GitRepository.parseHead("88dc125aa0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5\n") == .detached("88dc125"))
        #expect(GitRepository.parseHead("garbage") == nil)
    }

    @Test func originIsPreferredAmongRemotes() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "upstream"]
        \turl = https://github.com/apple/swift.git
        [remote "origin"]
        \turl = git@github.com:jstilwell/HoverEnhance.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        """
        #expect(GitRepository.remote(inConfig: config) == "git@github.com:jstilwell/HoverEnhance.git")
        #expect(GitRepository.remote(inConfig: "[remote \"fork\"]\n\turl = /tmp/fork\n") == "/tmp/fork")
        #expect(GitRepository.remote(inConfig: "[core]\n\tbare = false\n") == nil)
    }

    @Test func remotesAreShownWithoutSecrets() {
        #expect(GitRepository.withoutCredentials("https://ghp_secret@github.com/a/b.git") == "https://github.com/a/b.git")
        #expect(GitRepository.withoutCredentials("https://user:pass@example.com/a.git") == "https://example.com/a.git")
        #expect(GitRepository.withoutCredentials("ssh://git@example.com/a.git") == "ssh://git@example.com/a.git")
        #expect(GitRepository.withoutCredentials("git@github.com:a/b.git") == "git@github.com:a/b.git")

        #expect(GitRepository.displayRemote("git@github.com:jstilwell/HoverEnhance.git") == "github.com/jstilwell/HoverEnhance")
        #expect(GitRepository.displayRemote("https://gitlab.com/group/project.git") == "gitlab.com/group/project")
        #expect(GitRepository.displayRemote("ssh://git@git.example.com:2222/team/repo.git") == "git.example.com/team/repo")
        #expect(GitRepository.webPage(of: "git@github.com:a/b.git") == URL(string: "https://github.com/a/b"))
        #expect(GitRepository.webPage(of: "ssh://git@git.example.com/team/repo.git") == nil)
    }

    @Test func repositoriesReadTheirBranchAndRemote() async throws {
        let scratch = try Scratch()
        let repo = scratch.folder.appending(path: "repo", directoryHint: .isDirectory)
        let path = repo.path(percentEncoded: false)
        func run(_ arguments: [String]) throws {
            // Only the test runs Git, to make a real repository; the app reads it without Git.
            #expect(try scratch.run("/usr/bin/git", ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-C", path] + arguments) == 0)
        }
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try run(["init", "-q", "-b", "main"])
        try run(["remote", "add", "origin", "https://token123@github.com/someone/project.git"])
        try Data("one".utf8).write(to: repo.appending(path: "a.txt"))
        try run(["add", "a.txt"])
        try run(["commit", "-q", "-m", "first"])

        #expect(GitRepository.read(repo) == GitRepository(head: .branch("main"), remote: "https://github.com/someone/project.git"))

        // A worktree's .git is a file pointing at the real one; its remote comes from the main repository.
        let worktree = scratch.folder.appending(path: "worktree", directoryHint: .isDirectory)
        try run(["worktree", "add", "-q", "-b", "side", worktree.path(percentEncoded: false)])
        #expect(GitRepository.read(worktree) == GitRepository(head: .branch("side"), remote: "https://github.com/someone/project.git"))
        // However the folder's URL is written.
        #expect(GitRepository.read(URL(filePath: String(worktree.path(percentEncoded: false).dropLast())))?.head == .branch("side"))

        #expect(GitRepository.read(scratch.folder) == nil)
    }

    @Test func aCommonDirectoryIsFoundInsideTheGitDirectory() throws {
        let scratch = try Scratch()
        let gitDirectory = scratch.folder.appending(path: ".git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gitDirectory.appending(path: "shared"), withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8).write(to: gitDirectory.appending(path: "HEAD"))
        try Data("shared\n".utf8).write(to: gitDirectory.appending(path: "commondir"))
        try Data("[remote \"origin\"]\n\turl = https://example.com/inside.git\n".utf8).write(to: gitDirectory.appending(path: "shared/config"))
        // Where it would be if `commondir` were taken as relative to the folder instead, as it once was.
        try FileManager.default.createDirectory(at: scratch.folder.appending(path: "shared"), withIntermediateDirectories: true)
        try Data("[remote \"origin\"]\n\turl = https://example.com/outside.git\n".utf8).write(to: scratch.folder.appending(path: "shared/config"))

        #expect(GitRepository.read(scratch.folder)?.remote == "https://example.com/inside.git")
    }

    @Test func hoveringARepositoryRunsNothingInIt() throws {
        let scratch = try Scratch()
        let marker = scratch.folder.appending(path: "ran")
        let payload = scratch.folder.appending(path: "payload.sh")
        try Data("#!/bin/sh\ntouch '\(marker.path(percentEncoded: false))'\n".utf8).write(to: payload)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: payload.path(percentEncoded: false))
        let repo = scratch.folder.appending(path: "repo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8).write(to: repo.appending(path: ".git/HEAD"))
        let config = "[core]\n\tfsmonitor = \(payload.path(percentEncoded: false))\n[filter \"evil\"]\n\tclean = \(payload.path(percentEncoded: false))\n"
        try Data(config.utf8).write(to: repo.appending(path: ".git/config"))
        try Data("* filter=evil\n".utf8).write(to: repo.appending(path: ".gitattributes"))
        try Data("x".utf8).write(to: repo.appending(path: "file.txt"))

        let details = FileDetails.load(repo, options: FileCardOptions())
        #expect(details.git?.head == .branch("main"))
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test func gitRows() {
        var details = FileDetails()
        details.git = GitRepository(head: .detached("88dc125"), remote: "git@github.com:a/b.git")
        let rows = details.rows(pathStyle: .full)
        #expect(rows.map(\.label) == ["Branch", "Remote"])
        #expect(rows[0].value == .text("Detached at 88dc125") && rows[0].copyText == "88dc125")
        #expect(rows[1].value == .link("github.com/a/b", URL(string: "https://github.com/a/b")!))
        #expect(rows[1].copyText == "git@github.com:a/b.git")
    }
}

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

    @Test func repositoriesReadTheirBranchRemoteAndChanges() async throws {
        let git = try #require(GitRepository.executable, "the developer tools' Git is needed")
        let scratch = try Scratch()
        let repo = scratch.folder.appending(path: "repo", directoryHint: .isDirectory)
        let path = repo.path(percentEncoded: false)
        let gitPath = git.path(percentEncoded: false)
        func run(_ arguments: [String]) throws {
            #expect(try scratch.run(gitPath, ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-C", path] + arguments) == 0)
        }
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try run(["init", "-q", "-b", "main"])
        try run(["remote", "add", "origin", "https://token123@github.com/someone/project.git"])
        try Data("one".utf8).write(to: repo.appending(path: "a.txt"))
        try run(["add", "a.txt"])
        try run(["commit", "-q", "-m", "first"])

        #expect(GitRepository.read(repo) == GitRepository(head: .branch("main"), remote: "https://github.com/someone/project.git"))
        #expect(await GitRepository.changeCount(in: repo) == 0)
        try Data("changed".utf8).write(to: repo.appending(path: "a.txt"))
        try Data("new".utf8).write(to: repo.appending(path: "b.txt"))
        #expect(await GitRepository.changeCount(in: repo) == 2)

        // A worktree's .git is a file pointing at the real one; its remote comes from the main repository.
        let worktree = scratch.folder.appending(path: "worktree", directoryHint: .isDirectory)
        try run(["worktree", "add", "-q", "-b", "side", worktree.path(percentEncoded: false)])
        #expect(GitRepository.read(worktree) == GitRepository(head: .branch("side"), remote: "https://github.com/someone/project.git"))

        #expect(GitRepository.read(scratch.folder) == nil)
        #expect(await GitRepository.changeCount(in: scratch.folder) == nil)
    }

    @Test func repositoriesThatWouldRunCommandsArentAsked() async throws {
        let git = try #require(GitRepository.executable, "the developer tools' Git is needed")
        let scratch = try Scratch()
        let marker = scratch.folder.appending(path: "ran")
        let payload = scratch.folder.appending(path: "payload.sh")
        try Data("#!/bin/sh\ntouch '\(marker.path(percentEncoded: false))'\n".utf8).write(to: payload)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: payload.path(percentEncoded: false))

        func repository(_ name: String, config: String) throws -> URL {
            let repo = scratch.folder.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            #expect(try scratch.run(git.path(percentEncoded: false), ["-C", repo.path(percentEncoded: false), "init", "-q"]) == 0)
            let handle = try FileHandle(forWritingTo: repo.appending(path: ".git/config"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(config.utf8))
            try handle.close()
            try Data("x".utf8).write(to: repo.appending(path: "file.txt"))
            try Data("* filter=evil\n".utf8).write(to: repo.appending(path: ".gitattributes"))
            return repo
        }
        let payloadPath = payload.path(percentEncoded: false)

        // A file system monitor is switched off from the command line, so this one is asked, safely.
        let monitor = try repository("monitor", config: "[core]\n\tfsmonitor = \(payloadPath)\n")
        #expect(await GitRepository.changeCount(in: monitor) == 2)
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))

        // Filters can't be, so a repository defining one, or pulling in other settings, isn't asked.
        let filter = try repository("filter", config: "[filter \"evil\"]\n\tclean = \(payloadPath)\n")
        #expect(await GitRepository.changeCount(in: filter) == nil)
        let include = try repository("include", config: "[include]\n\tpath = ../../elsewhere.config\n")
        #expect(await GitRepository.changeCount(in: include) == nil)
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))

        // A config Git could read but HoverEnhance can't is refused too.
        let unreadable = try repository("unreadable", config: "")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.appending(path: ".git/config").path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.appending(path: ".git/config").path(percentEncoded: false)) }
        #expect(GitRepository.configRunsCommands(unreadable))
        #expect(!GitRepository.configRunsCommands(monitor))
    }

    @Test func configChecksIgnoreCaseAndBadBytes() {
        func runs(_ text: String) -> Bool { GitRepository.configMayRunCommands(Data(text.utf8)) }
        #expect(runs("[includeIf \"gitdir:~/work/\"]\n\tpath = x"))
        #expect(runs("[FILTER \"x\"]\n\tClean = y"))
        #expect(runs("[filter.x]\nclean = y"))
        #expect(runs("[core] sshCommand = evil"))
        #expect(runs("[extensions]\n\tpartialClone = origin"))
        #expect(runs("[remote \"origin\"]\n\tpromisor = true"))
        // Bytes that aren't UTF-8 can't hide a filter.
        #expect(GitRepository.configMayRunCommands(Data([0xFF, 0xFE]) + Data("[filter \"x\"]".utf8) + Data([0xC3])))
        #expect(!runs("[core]\n\tbare = false\n\tfsmonitor = true\n[remote \"origin\"]\n\turl = git@github.com:a/b.git"))
    }

    @Test func aHungGitIsGivenUpOn() async throws {
        let scratch = try Scratch()
        let slow = scratch.folder.appending(path: "slow-git")
        // The sleep is a child that keeps the output open after the script itself is stopped.
        try Data("#!/bin/sh\nsleep 10\ntrue\n".utf8).write(to: slow)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slow.path(percentEncoded: false))
        // Looks enough like a repository for Git to be run.
        try FileManager.default.createDirectory(at: scratch.folder.appending(path: ".git"), withIntermediateDirectories: true)
        let start = Date()
        #expect(await GitRepository.changeCount(in: scratch.folder, git: slow, timeout: 0.3) == nil)
        #expect(Date().timeIntervalSince(start) > 0.25)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func gitRowsAndChangeCounts() {
        var details = FileDetails()
        details.git = GitRepository(head: .detached("88dc125"), remote: "git@github.com:a/b.git")
        let rows = details.rows(pathStyle: .full, changes: .found(3))
        #expect(rows.map(\.label) == ["Branch", "Remote", "Changes"])
        #expect(rows[0].value == .text("Detached at 88dc125") && rows[0].copyText == "88dc125")
        #expect(rows[1].value == .link("github.com/a/b", URL(string: "https://github.com/a/b")!))
        #expect(rows[1].copyText == "git@github.com:a/b.git")
        #expect(rows[2].value == .text("3 uncommitted changes"))
        #expect(details.rows(pathStyle: .full, changes: .found(0)).last?.value == .text("None"))
    }
}

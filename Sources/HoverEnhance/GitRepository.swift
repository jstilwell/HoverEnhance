import Foundation

/// A Git repository's branch and remote, read from its files, and its uncommitted changes, from Git.
struct GitRepository: Sendable, Equatable {
    enum Head: Sendable, Equatable {
        case branch(String)
        /// A commit checked out directly, by its short hash.
        case detached(String)
    }

    var head: Head?
    /// The origin remote's URL, or the first remote's, with any credentials taken out.
    var remote: String?

    /// Nil unless `folder` is the top of a repository. Reads `.git` directly rather than running Git.
    static func read(_ folder: URL) -> GitRepository? {
        guard let gitDirectory = gitDirectory(of: folder) else { return nil }
        let common = commonDirectory(of: gitDirectory)
        let head = (try? String(contentsOf: gitDirectory.appending(path: "HEAD"), encoding: .utf8)).flatMap(parseHead)
        let config = try? String(contentsOf: common.appending(path: "config"), encoding: .utf8)
        return GitRepository(head: head, remote: config.flatMap(remote(inConfig:)).map(withoutCredentials))
    }

    /// Worktrees keep their own HEAD but share the main repository's config.
    private static func commonDirectory(of gitDirectory: URL) -> URL {
        (try? String(contentsOf: gitDirectory.appending(path: "commondir"), encoding: .utf8))
            .map { URL(filePath: $0.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: gitDirectory).standardized } ?? gitDirectory
    }

    /// `.git` is a folder, or for worktrees and submodules a file naming the real one.
    private static func gitDirectory(of folder: URL) -> URL? {
        let dotGit = folder.appending(path: ".git")
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path(percentEncoded: false), isDirectory: &isFolder) else { return nil }
        if isFolder.boolValue { return dotGit }
        guard let text = try? String(contentsOf: dotGit, encoding: .utf8), text.hasPrefix("gitdir:") else { return nil }
        let path = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(filePath: path, directoryHint: .isDirectory, relativeTo: folder).standardized
    }

    static func parseHead(_ text: String) -> Head? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") { return .branch(String(line.dropFirst("ref: refs/heads/".count))) }
        if line.count >= 7, line.allSatisfy(\.isHexDigit) { return .detached(String(line.prefix(7))) }
        return nil
    }

    /// The `url` of `[remote "origin"]`, or of the first remote listed.
    static func remote(inConfig config: String) -> String? {
        var remotes: [(name: String, url: String)] = []
        var section: String?
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                // [remote "origin"]
                let parts = line.dropFirst().dropLast().split(separator: "\"")
                section = parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces) == "remote" ? String(parts[1]) : nil
            } else if let name = section, let equals = line.firstIndex(of: "="),
                      line[..<equals].trimmingCharacters(in: .whitespaces) == "url" {
                remotes.append((name, line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)))
            }
        }
        return (remotes.first { $0.name == "origin" } ?? remotes.first)?.url
    }

    /// An https remote can carry a token as its user or password ("https://token@host/…"); it
    /// shouldn't be shown or copied. An ssh remote's user ("ssh://git@host/…") is needed and kept.
    static func withoutCredentials(_ remote: String) -> String {
        guard var components = URLComponents(string: remote), let scheme = components.scheme?.lowercased(),
              components.user != nil || components.password != nil else { return remote }
        components.password = nil
        if scheme == "http" || scheme == "https" { components.user = nil }
        return components.string ?? remote
    }

    /// "github.com/jstilwell/HoverEnhance", from the https or scp-style ("git@host:path") URL.
    static func displayRemote(_ remote: String) -> String {
        var text = remote
        if let components = URLComponents(string: remote), let host = components.host {
            text = host + components.path
        } else if let at = remote.firstIndex(of: "@"), let colon = remote[at...].firstIndex(of: ":") {
            text = remote[remote.index(after: at)..<colon] + "/" + remote[remote.index(after: colon)...]
        }
        if text.hasSuffix(".git") { text.removeLast(4) }
        return text
    }

    /// The remote's web page, for hosts known to have one at the same path.
    static func webPage(of remote: String) -> URL? {
        let page = displayRemote(remote)
        let hosts = ["github.com", "gitlab.com", "bitbucket.org", "codeberg.org"]
        guard hosts.contains(where: { page.hasPrefix($0 + "/") }) else { return nil }
        return URL(string: "https://" + page)
    }

    // MARK: - Uncommitted changes

    /// The real Git. `/usr/bin/git` is a stub that, on Macs without the developer tools, offers to
    /// install them; this skips it.
    static let executable: URL? = {
        var candidates = ["/Library/Developer/CommandLineTools/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        if let developer = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link") {
            candidates.insert(developer + "/usr/bin/git", at: 0)
        }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(filePath: $0) }
    }()

    /// How many files have uncommitted changes, counting new ones. Nil when Git isn't installed,
    /// refuses, takes longer than `timeout` (as it can in a very large repository), or when the
    /// repository's own settings could make Git run commands.
    static func changeCount(in folder: URL, git: URL? = executable, timeout: TimeInterval = 3) async -> Int? {
        guard let git, !configRunsCommands(folder) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runStatus(git, in: folder, timeout: timeout))
            }
        }
    }

    /// Whether the repository's settings could run commands that `-c` can't switch off: clean and
    /// smudge filters (run to compare changed files, and named per filter), other config files pulled
    /// in that might define them, or fetching missing objects in a partial clone, which can run its ssh
    /// command. A repository from elsewhere, such as an unzipped download, is the user's own as far as
    /// Git can tell, so this stands between a hover and its commands. It errs toward refusing: a config
    /// that can't be read counts, and so does any mention of these words, wherever it is.
    static func configRunsCommands(_ folder: URL) -> Bool {
        guard let gitDirectory = gitDirectory(of: folder) else { return true }
        let common = commonDirectory(of: gitDirectory)
        let configs = [common.appending(path: "config"), common.appending(path: "config.worktree"),
                       gitDirectory.appending(path: "config"), gitDirectory.appending(path: "config.worktree")]
        return configs.contains { url in
            let path = url.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path) else { return false }
            guard let data = FileManager.default.contents(atPath: path) else { return true }
            return configMayRunCommands(data)
        }
    }

    /// Git reads config as bytes and its names ignore case, so this looks at the bytes, ignoring case.
    static func configMayRunCommands(_ config: Data) -> Bool {
        let text = String(decoding: config, as: UTF8.self).lowercased()
        return ["filter", "include", "sshcommand", "promisor", "partialclone"].contains { text.contains($0) }
    }

    private static func runStatus(_ git: URL, in folder: URL, timeout: TimeInterval) -> Int? {
        // Output goes to a file rather than a pipe: something Git starts in the background, such as
        // its file system monitor, could otherwise hold the pipe open and keep this waiting forever.
        let file = FileManager.default.temporaryDirectory.appending(path: "HoverEnhance-git-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil),
              let output = try? FileHandle(forWritingTo: file) else { return nil }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: file)
        }
        let process = Process()
        process.executableURL = git
        process.arguments = [
            // Settings given here outrank the repository's, which could otherwise name a program for
            // Git to run just because the folder was hovered.
            "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
            // No optional locks: this mustn't write the index or block the user's own Git commands.
            "--no-optional-locks", "-C", folder.path(percentEncoded: false),
            // Submodules have settings of their own, which aren't checked; leave them out. Without
            // renames, Git has no reason to read what's in the files.
            "status", "--porcelain", "--untracked-files=normal", "--ignore-submodules=all", "--no-renames",
        ]
        var environment = ProcessInfo.processInfo.environment
        // Never fetch missing objects, and never ask for a password.
        environment["GIT_NO_LAZY_FETCH"] = "1"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        guard (try? process.run()) != nil else { return nil }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let data = try? Data(contentsOf: file) else { return nil }
        return data.split(separator: UInt8(ascii: "\n")).count
    }
}

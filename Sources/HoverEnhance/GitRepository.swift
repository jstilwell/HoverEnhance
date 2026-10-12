import Foundation

/// A Git repository's branch and remote, read from its files. Git itself is never run: a repository's
/// settings can have it run commands, and a hovered folder may have come from anywhere.
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
        let head = text(at: gitDirectory.appending(path: "HEAD")).flatMap(parseHead)
        let config = text(at: common.appending(path: "config"))
        return GitRepository(head: head, remote: config.flatMap(remote(inConfig:)).map(withoutCredentials))
    }

    /// Worktrees keep their own HEAD but share the main repository's config.
    private static func commonDirectory(of gitDirectory: URL) -> URL {
        text(at: gitDirectory.appending(path: "commondir")).map {
            URL(filePath: $0.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory, relativeTo: gitDirectory).standardized
        } ?? gitDirectory
    }

    /// `.git` is a folder, or for worktrees and submodules a file naming the real one. Either way the Git
    /// directory comes back as a directory URL, since paths in it (`commondir`) are relative to it.
    private static func gitDirectory(of folder: URL) -> URL? {
        let folder = URL(filePath: folder.path(percentEncoded: false), directoryHint: .isDirectory)
        let dotGit = folder.appending(path: ".git")
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path(percentEncoded: false), isDirectory: &isFolder) else { return nil }
        if isFolder.boolValue { return folder.appending(path: ".git", directoryHint: .isDirectory) }
        guard let text = text(at: dotGit), text.hasPrefix("gitdir:") else { return nil }
        let path = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(filePath: path, directoryHint: .isDirectory, relativeTo: folder).standardized
    }

    /// The start of a small file. A repository can come from anywhere, and these files are never large in
    /// a real one, so a huge one isn't read whole.
    private static func text(at url: URL, upTo limit: Int = 1 << 20) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: limit)).map { String(decoding: $0, as: UTF8.self) }
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
}

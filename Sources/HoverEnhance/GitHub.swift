import Foundation

/// A repository, issue, or pull request a link points at.
enum GitHubRef: Sendable, Hashable {
    case repo(owner: String, name: String)
    case issue(owner: String, name: String, number: Int)
    case pull(owner: String, name: String, number: Int)
}

/// What a card shows about a repository.
struct GitHubRepo: Sendable, Equatable {
    let fullName: String
    let description: String?
    let stars: Int
    let forks: Int
    let language: String?
    /// Its SPDX id, such as "MIT", when GitHub recognizes it.
    let license: String?
    let topics: [String]
    let pushed: Date?
    let isArchived: Bool
    let isFork: Bool
    let isOrganization: Bool
    let avatar: URL?
    let url: URL
}

/// What a card shows about an issue or pull request.
struct GitHubIssue: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case open, draft, merged
        /// Closed as done, or for a pull request, closed without merging.
        case closed
        /// An issue closed as not planned, or as a duplicate.
        case notPlanned
    }

    struct Label: Sendable, Equatable {
        let name: String
        /// Hex RGB, without a #.
        let color: String
    }

    let repo: String
    let number: Int
    let title: String
    let isPull: Bool
    let state: State
    let author: String?
    let avatar: URL?
    let created: Date?
    /// The start of its description, as plain text.
    let excerpt: String
    let labels: [Label]
    let comments: Int
    /// Lines and files a pull request changes; nil for issues, and for a pull request reached by its issue.
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let url: URL
}

enum GitHubCard: Sendable, Equatable {
    case repo(GitHubRepo)
    case issue(GitHubIssue)

    var url: URL {
        switch self {
        case .repo(let repo): repo.url
        case .issue(let issue): issue.url
        }
    }
}

enum GitHub {
    static func isGitHub(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    /// The first part of github.com paths that aren't an owner's.
    private static let reserved: Set<String> = [
        "about", "apps", "codespaces", "collections", "contact", "customer-stories", "enterprise", "events", "explore",
        "features", "issues", "join", "login", "logout", "marketplace", "new", "notifications", "orgs", "organizations",
        "pricing", "pulls", "readme", "search", "security", "settings", "site", "sponsors", "team", "topics", "trending",
    ]

    /// github.com/<owner>/<repo>, its issues/<n> and pull/<n>, and anything else inside it, which is about
    /// the repository too.
    static func ref(fromLink url: URL) -> GitHubRef? {
        guard ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host()?.lowercased(),
              host == "github.com" || host == "www.github.com" else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        guard parts.count >= 2, !reserved.contains(parts[0].lowercased()) else { return nil }
        let owner = parts[0]
        let name = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        guard isName(owner, allowingDots: false), isName(name, allowingDots: true), name != ".", name != ".." else { return nil }
        if parts.count >= 4, let number = Int(parts[3]), number > 0, parts[3].count <= 9 {
            switch parts[2] {
            case "issues": return .issue(owner: owner, name: name, number: number)
            case "pull": return .pull(owner: owner, name: name, number: number)
            default: break
            }
        }
        return .repo(owner: owner, name: name)
    }

    private static func isName(_ string: String, allowingDots: Bool) -> Bool {
        (1...100).contains(string.count)
            && string.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || (allowingDots && $0 == ".")) }
    }

    static func apiURL(for ref: GitHubRef) -> URL {
        let path = switch ref {
        case .repo(let owner, let name): "repos/\(owner)/\(name)"
        case .issue(let owner, let name, let number): "repos/\(owner)/\(name)/issues/\(number)"
        case .pull(let owner, let name, let number): "repos/\(owner)/\(name)/pulls/\(number)"
        }
        return URL(string: "https://api.github.com/\(path)")!
    }

    static let headers = ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]

    static func card(_ data: Data, for ref: GitHubRef) -> GitHubCard? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        switch ref {
        case .repo:
            return (try? decoder.decode(RepoResponse.self, from: data)).flatMap(repo).map(GitHubCard.repo)
        case .issue(let owner, let name, _), .pull(let owner, let name, _):
            return (try? decoder.decode(IssueResponse.self, from: data)).flatMap { issue($0, repo: "\(owner)/\(name)") }.map(GitHubCard.issue)
        }
    }

    private struct User: Decodable {
        let login: String
        let avatar_url: String?
        let type: String?
    }

    private struct RepoResponse: Decodable {
        struct License: Decodable { let spdx_id: String? }
        let full_name: String
        let html_url: String
        let description: String?
        let stargazers_count: Int
        let forks_count: Int
        let language: String?
        let license: License?
        let topics: [String]?
        let pushed_at: Date?
        let archived: Bool?
        let fork: Bool?
        let owner: User
    }

    private static func repo(_ response: RepoResponse) -> GitHubRepo? {
        guard let url = URL(string: response.html_url) else { return nil }
        // "NOASSERTION" is a license GitHub couldn't name.
        let license = response.license?.spdx_id.flatMap { $0 == "NOASSERTION" ? nil : $0 }
        return GitHubRepo(
            fullName: response.full_name, description: response.description.flatMap { $0.isEmpty ? nil : $0 },
            stars: response.stargazers_count, forks: response.forks_count, language: response.language, license: license,
            topics: response.topics ?? [], pushed: response.pushed_at, isArchived: response.archived ?? false,
            isFork: response.fork ?? false, isOrganization: response.owner.type == "Organization", avatar: response.owner.avatar_url.flatMap(URL.init(string:)), url: url
        )
    }

    /// An issue, or a pull request from the issues API or the pulls API, which share most fields.
    private struct IssueResponse: Decodable {
        struct Label: Decodable { let name: String; let color: String? }
        /// On an issue that's really a pull request.
        struct PullLink: Decodable { let merged_at: Date? }
        let number: Int
        let title: String
        let html_url: String
        let state: String
        let state_reason: String?
        let draft: Bool?
        let user: User?
        let created_at: Date?
        let body: String?
        let labels: [Label]?
        let comments: Int?
        let pull_request: PullLink?
        // The pulls API only.
        let merged_at: Date?
        let additions: Int?
        let deletions: Int?
        let changed_files: Int?
    }

    private static func issue(_ response: IssueResponse, repo: String) -> GitHubIssue? {
        guard let url = URL(string: response.html_url) else { return nil }
        let isPull = response.pull_request != nil || response.additions != nil || url.pathComponents.contains("pull")
        let merged = response.merged_at ?? response.pull_request?.merged_at
        let state: GitHubIssue.State = switch (response.state, isPull) {
        case ("open", _): response.draft == true ? .draft : .open
        case (_, true): merged != nil ? .merged : .closed
        default: response.state_reason == "not_planned" || response.state_reason == "duplicate" ? .notPlanned : .closed
        }
        return GitHubIssue(
            repo: repo, number: response.number, title: response.title, isPull: isPull, state: state,
            author: response.user?.login, avatar: response.user?.avatar_url.flatMap(URL.init(string:)), created: response.created_at,
            excerpt: excerpt(of: response.body ?? ""),
            labels: (response.labels ?? []).map { GitHubIssue.Label(name: $0.name, color: $0.color ?? "8b949e") },
            comments: response.comments ?? 0, additions: response.additions, deletions: response.deletions,
            changedFiles: response.changed_files, url: url
        )
    }

    /// The start of a Markdown description as plain text: without HTML comments (often a template's), images,
    /// and markup, its lines run together.
    static func excerpt(of body: String, limit: Int = 300) -> String {
        var text = body.replacing(/<!--[\s\S]*?-->/, with: "")
        text = text.replacing(/!\[[^\]]*\]\([^)]*\)/, with: "")
        text = text.replacing(/<[^>]+>/, with: "")
        text = text.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.1) }
        text = text.replacing(/(?m)^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+/, with: "")
        text = text.replacing(/[*_`~]{1,3}/, with: "")
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.count > limit ? String(words.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : words
    }
}

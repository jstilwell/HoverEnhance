import AppKit
import SwiftUI

/// What the preview shows for a link to a GitHub repository, issue, or pull request, in GitHub's look.
/// Clicking it opens the link.
struct GitHubCardView: View {
    let card: GitHubCard

    static let width: CGFloat = 440

    var body: some View {
        Button { NSWorkspace.shared.open(card.url) } label: {
            Group {
                switch card {
                case .repo(let repo): RepoCard(repo: repo)
                case .issue(let issue): IssueCard(issue: issue)
                }
            }
            .padding(16)
            .frame(width: Self.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open on GitHub")
        .foregroundStyle(GitHubTheme.text)
        .background(GitHubTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: PreviewPanel.cornerRadius - PreviewGeometry.padding))
    }
}

private struct RepoCard: View {
    let repo: GitHubRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // GitHub draws organizations' avatars square, and people's round.
                Avatar(url: repo.avatar, size: 20, square: repo.isOrganization)
                Text(repo.fullName).font(.system(size: 15, weight: .semibold)).foregroundStyle(GitHubTheme.accent).lineLimit(1)
                if repo.isArchived {
                    Badge(text: "Public archive", color: GitHubTheme.attention)
                } else if repo.isFork {
                    Badge(text: "Fork", color: GitHubTheme.muted)
                }
            }
            if let description = repo.description {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(GitHubTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !repo.topics.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(repo.topics.prefix(6), id: \.self) { topic in
                        Text(topic)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GitHubTheme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(GitHubTheme.topic, in: Capsule())
                    }
                }
            }
            HStack(spacing: 14) {
                if let language = repo.language {
                    HStack(spacing: 5) {
                        Circle().fill(GitHubTheme.color(of: language)).frame(width: 10, height: 10)
                        Text(language)
                    }
                }
                Label(GitHubFormat.count(repo.stars), systemImage: "star").accessibilityLabel("\(repo.stars) stars")
                Label(GitHubFormat.count(repo.forks), systemImage: "arrow.triangle.branch").accessibilityLabel("\(repo.forks) forks")
                if let license = repo.license {
                    Label(license, systemImage: "scalemass")
                }
                if let pushed = repo.pushed {
                    Label(GitHubFormat.age(pushed), systemImage: "clock").help("Last pushed to").lineLimit(1)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(GitHubTheme.muted)
            .lineLimit(1)
        }
    }
}

private struct IssueCard: View {
    let issue: GitHubIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(issue.repo)
                Text(verbatim: "#\(issue.number)")
                if let created = issue.created {
                    Text("· \(GitHubFormat.age(created))")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(GitHubTheme.muted)
            .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: stateSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(stateColor)
                    .accessibilityLabel(stateName)
                Text(issue.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !issue.excerpt.isEmpty {
                Text(issue.excerpt)
                    .font(.system(size: 13))
                    .foregroundStyle(GitHubTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !issue.labels.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(Array(issue.labels.prefix(6).enumerated()), id: \.offset) { _, label in
                        LabelChip(label: label)
                    }
                }
            }
            HStack(spacing: 14) {
                Text(stateName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(stateColor, in: Capsule())
                if let author = issue.author {
                    HStack(spacing: 5) {
                        Avatar(url: issue.avatar, size: 16, square: false)
                        Text(author).lineLimit(1)
                    }
                }
                if issue.comments > 0 {
                    Label("\(issue.comments)", systemImage: "bubble.left").accessibilityLabel("\(issue.comments) comments")
                }
                if let additions = issue.additions, let deletions = issue.deletions {
                    HStack(spacing: 4) {
                        Text("+\(additions.formatted())").foregroundStyle(GitHubTheme.success)
                        Text("−\(deletions.formatted())").foregroundStyle(GitHubTheme.danger)
                    }
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                if let files = issue.changedFiles {
                    Text(files == 1 ? "1 file" : "\(files.formatted()) files")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(GitHubTheme.muted)
            .lineLimit(1)
            .padding(.top, 2)
        }
    }

    private var stateName: String {
        switch issue.state {
        case .open: "Open"
        case .draft: "Draft"
        case .merged: "Merged"
        case .closed: "Closed"
        case .notPlanned: "Not planned"
        }
    }

    private var stateSymbol: String {
        switch (issue.state, issue.isPull) {
        case (.merged, _): "arrow.triangle.merge"
        case (_, true): "arrow.triangle.pull"
        case (.open, false), (.draft, false): "smallcircle.filled.circle"
        case (.closed, false): "checkmark.circle"
        case (.notPlanned, false): "slash.circle"
        }
    }

    /// GitHub's: green while open, purple once done, gray for drafts and issues not planned, and red for a
    /// pull request closed without merging.
    private var stateColor: Color {
        switch (issue.state, issue.isPull) {
        case (.open, _): GitHubTheme.success
        case (.merged, _), (.closed, false): GitHubTheme.done
        case (.closed, true): GitHubTheme.danger
        case (.draft, _), (.notPlanned, _): GitHubTheme.neutral
        }
    }
}

/// A label in its own color, with text that reads on it.
private struct LabelChip: View {
    let label: GitHubIssue.Label

    var body: some View {
        let rgb = UInt32(label.color, radix: 16) ?? 0x8B949E
        let (red, green, blue) = (Double(rgb >> 16 & 0xFF) / 255, Double(rgb >> 8 & 0xFF) / 255, Double(rgb & 0xFF) / 255)
        let isLight = 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
        Text(label.name)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(isLight ? Color.black.opacity(0.85) : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(red: red, green: green, blue: blue), in: Capsule())
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(color.opacity(0.6)))
            .fixedSize()
    }
}

private struct Avatar: View {
    let url: URL?
    let size: CGFloat
    let square: Bool

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            GitHubTheme.topic
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: square ? size / 5 : size / 2))
        .accessibilityHidden(true)
    }
}

/// Lays its children out in rows, wrapping to a new row when one is full.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.indices + [index], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

/// GitHub's Primer colors, light and dark.
enum GitHubTheme {
    static let background = Color(light: 0xFFFFFF, dark: 0x0D1117)
    static let text = Color(light: 0x1F2328, dark: 0xF0F6FC)
    static let muted = Color(light: 0x59636E, dark: 0x9198A1)
    static let accent = Color(light: 0x0969DA, dark: 0x4493F8)
    static let topic = Color(light: 0xDDF4FF, dark: 0x121D2F)
    static let success = Color(light: 0x1A7F37, dark: 0x3FB950)
    static let done = Color(light: 0x8250DF, dark: 0xAB7DF8)
    static let danger = Color(light: 0xD1242F, dark: 0xF85149)
    static let neutral = Color(light: 0x59636E, dark: 0x9198A1)
    static let attention = Color(light: 0x9A6700, dark: 0xD29922)

    /// The dot GitHub shows beside a repository's main language, from github-linguist, for the common ones.
    static func color(of language: String) -> Color {
        let colors: [String: UInt32] = [
            "C": 0x555555, "C#": 0x178600, "C++": 0xF34B7D, "CSS": 0x663399, "Dart": 0x00B4AB, "Dockerfile": 0x384D54,
            "Elixir": 0x6E4A7E, "Go": 0x00ADD8, "Haskell": 0x5E5086, "HTML": 0xE34C26, "Java": 0xB07219,
            "JavaScript": 0xF1E05A, "Jupyter Notebook": 0xDA5B0B, "Kotlin": 0xA97BFF, "Lua": 0x000080, "Nix": 0x7E7EFF,
            "Objective-C": 0x438EFF, "Perl": 0x0298C3, "PHP": 0x4F5D95, "PowerShell": 0x012456, "Python": 0x3572A5,
            "R": 0x198CE7, "Ruby": 0x701516, "Rust": 0xDEA584, "Scala": 0xC22D40, "Shell": 0x89E051, "Svelte": 0xFF3E00,
            "Swift": 0xF05138, "TypeScript": 0x3178C6, "Vue": 0x41B883, "Zig": 0xEC915C,
        ]
        let hex = colors[language] ?? 0x8B949E
        return Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Counts the way GitHub writes them: "999", "1.2k", "70.5k".
enum GitHubFormat {
    /// "39 min. ago", short enough for a line of numbers.
    static func age(_ date: Date, relativeTo now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    static func count(_ number: Int) -> String {
        guard number >= 1000 else { return "\(number)" }
        let thousands = Double(number) / 1000
        if thousands >= 1000 { return String(format: "%.1fm", thousands / 1000).replacingOccurrences(of: ".0m", with: "m") }
        return String(format: "%.1fk", thousands).replacingOccurrences(of: ".0k", with: "k")
    }
}

import AppKit
import SwiftUI

/// What file cards show; set in Settings → Finder.
struct FileCardOptions: Sendable, Equatable {
    var path = true
    var pathStyle = PathStyle.full
    var kindAndSize = true
    var dates = true
    var mediaInfo = true
    var whereFrom = true
    var users = true
    var offersQuit = true
}

extension PathStyle {
    /// `path` written this way. `home` is the folder `~` stands for.
    func format(_ path: String, home: String = NSHomeDirectory()) -> String {
        switch self {
        case .full: path
        case .tilde: path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        case .quoted: Self.shellQuoted(path)
        }
    }

    /// Single-quoted when it holds anything a shell would read specially; a quote inside becomes '\''.
    static func shellQuoted(_ path: String) -> String {
        guard path.isEmpty || path.unicodeScalars.contains(where: { !shellSafe.contains($0) }) else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static let shellSafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,:@")
}

/// What a file card shows about one file or folder.
@MainActor @Observable
final class FileCard {
    let url: URL
    let options: FileCardOptions
    let details: FileDetails
    let name: String
    let icon: NSImage
    /// As Finder's Copy as Pathname writes it: no trailing slash on folders.
    let path: String
    /// The path was just copied; the button shows a checkmark for a moment.
    private(set) var copied = false
    @ObservationIgnored private var copyGeneration = 0
    /// Who's using it; nil while looking.
    private(set) var users: [FileUser]?
    private(set) var userIcons: [pid_t: NSImage] = [:]
    private(set) var quitStates: [pid_t: QuitState] = [:]

    enum QuitState: Equatable {
        /// Clicked once; a second click quits.
        case confirming
        case quitting
        /// Asked to quit but still running, perhaps asking about unsaved changes. Force Quit is offered.
        case stillRunning
        case quit
        case failed
    }

    init(url: URL, details: FileDetails, options: FileCardOptions) {
        self.url = url
        self.details = details
        self.options = options
        path = Self.path(of: url)
        name = FileManager.default.displayName(atPath: path)
        icon = NSWorkspace.shared.icon(forFile: path)
    }

    nonisolated static func path(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    var formattedPath: String { options.pathStyle.format(path) }

    func loadUsers() async {
        guard options.users, users == nil else { return }
        let found = await FileUsers.find(url)
        for user in found {
            userIcons[user.pid] = NSRunningApplication(processIdentifier: user.pid)?.icon
                ?? user.executable.map(NSWorkspace.shared.icon(forFile:))
        }
        users = found
    }

    /// Quit takes a second click to confirm; if the process is still running after it's asked to
    /// quit, the button offers Force Quit.
    func quitClicked(_ user: FileUser) {
        switch quitStates[user.pid] {
        case nil, .failed:
            quitStates[user.pid] = .confirming
            Task {
                try? await Task.sleep(for: .seconds(4))
                if quitStates[user.pid] == .confirming { quitStates[user.pid] = nil }
            }
        case .confirming:
            Task { await quit(user, force: false) }
        case .stillRunning:
            Task { await quit(user, force: true) }
        case .quitting, .quit:
            break
        }
    }

    private func quit(_ user: FileUser, force: Bool) async {
        quitStates[user.pid] = .quitting
        guard FileUsers.quit(user.pid, force: force) else {
            quitStates[user.pid] = .failed
            return
        }
        // Apps can take a moment, or stop to ask about unsaved changes.
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if !FileUsers.isRunning(user.pid) {
                quitStates[user.pid] = .quit
                return
            }
        }
        quitStates[user.pid] = force ? .failed : .stillRunning
    }

    func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formattedPath, forType: .string)
        copied = true
        copyGeneration += 1
        let generation = copyGeneration
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if generation == copyGeneration { copied = false }
        }
    }
}

/// The card shown beside a file or folder in Finder.
struct FileCardView: View {
    let card: FileCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: card.icon).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.headline).lineLimit(2)
                    if !kindAndSize.isEmpty {
                        Text(kindAndSize).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if card.options.path {
                PathButton(card: card)
            }
            DetailsGrid(details: card.details)
            if card.options.users {
                UsersSection(card: card)
            }
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
        .task { await card.loadUsers() }
    }

    private var kindAndSize: String {
        let size = card.details.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [card.details.kind, size].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Dates, dimensions, length, pages, and where a download came from: whichever the file has.
private struct DetailsGrid: View {
    let details: FileDetails

    var body: some View {
        if hasAny {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Created", details.created.map(Self.dateFormatter.string(from:)))
                row("Modified", details.modified.map(Self.dateFormatter.string(from:)))
                row("Opened", details.opened.map(Self.dateFormatter.string(from:)))
                row("Dimensions", details.dimensions.map { "\($0.width) × \($0.height)" })
                row("Length", details.duration.map(FileDetails.formatDuration))
                row("Pages", details.pages.map(String.init))
                if let source = details.whereFrom {
                    GridRow {
                        Text("From").foregroundStyle(.secondary)
                        Button {
                            NSWorkspace.shared.open(source)
                        } label: {
                            HStack(spacing: 4) {
                                Text(FileDetails.formatSource(source)).lineLimit(1).truncationMode(.middle)
                                Image(systemName: "arrow.up.right.square")
                            }
                        }
                        .buttonStyle(.link)
                        .help(source.absoluteString)
                    }
                }
            }
            .font(.callout)
        }
    }

    private var hasAny: Bool {
        details.created != nil || details.modified != nil || details.opened != nil || details.dimensions != nil
            || details.duration != nil || details.pages != nil || details.whereFrom != nil
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value).lineLimit(1)
            }
        }
    }

    /// "Today at 5:05 PM", "Oct 8, 2026 at 1:54 PM".
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

/// The path, which copies itself when clicked.
private struct PathButton: View {
    let card: FileCard

    var body: some View {
        Button(action: card.copyPath) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.formattedPath)
                    .font(.system(.callout, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: card.copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(card.copied ? .green : .secondary)
                    .frame(width: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(card.copied ? "Copied" : "Copy the path")
    }
}

/// Who's using the file, each with a way to quit it.
private struct UsersSection: View {
    let card: FileCard
    private let maxRows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In use by").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            if let users = card.users {
                if users.isEmpty {
                    Text("Not in use").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(users.prefix(maxRows)) { user in
                    UserRow(card: card, user: user)
                }
                if users.count > maxRows {
                    Text("and \(users.count - maxRows) more").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct UserRow: View {
    let card: FileCard
    let user: FileUser

    var body: some View {
        HStack(spacing: 8) {
            if let icon = card.userIcons[user.pid] {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(user.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if card.options.offersQuit {
                QuitButton(card: card, user: user)
            }
        }
        .font(.callout)
        .opacity(card.quitStates[user.pid] == .quit ? 0.5 : 1)
    }

    private var detail: String {
        let use = switch user.use {
        case .running: "Running"
        case .window: "Open in a window"
        case .workingFolder: "Working in this folder"
        case .open: "Has it open"
        case .onVolume: "Has files open on it"
        }
        return "\(use) · pid \(user.pid)"
    }
}

private struct QuitButton: View {
    let card: FileCard
    let user: FileUser

    var body: some View {
        Group {
            switch card.quitStates[user.pid] {
            case nil:
                Button("Quit") { card.quitClicked(user) }
            case .confirming:
                // Red text rather than a red button: the panel is never the active window, and
                // inactive windows draw prominent buttons gray.
                Button { card.quitClicked(user) } label: { Text("Confirm Quit").foregroundStyle(.red) }
            case .quitting:
                ProgressView().controlSize(.small)
            case .stillRunning:
                Button { card.quitClicked(user) } label: { Text("Force Quit").foregroundStyle(.red) }
                    .help("It didn't quit; it may be asking about unsaved changes")
            case .quit:
                Label("Quit", systemImage: "checkmark").foregroundStyle(.secondary)
            case .failed:
                Button("Try Again") { card.quitClicked(user) }
                    .help("It couldn't be quit")
            }
        }
        .controlSize(.small)
    }
}

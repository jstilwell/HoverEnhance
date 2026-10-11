import AppKit
import SwiftUI

/// What file cards show; set in Settings → Finder.
struct FileCardOptions: Sendable, Equatable {
    var path = true
    var pathStyle = PathStyle.full
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
    let name: String
    let icon: NSImage
    /// As Finder's Copy as Pathname writes it: no trailing slash on folders.
    let path: String
    /// The path was just copied; the button shows a checkmark for a moment.
    private(set) var copied = false
    @ObservationIgnored private var copyGeneration = 0

    init(url: URL, options: FileCardOptions) {
        self.url = url
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
                Text(card.name).font(.headline).lineLimit(2)
            }
            if card.options.path {
                PathButton(card: card)
            }
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
    }
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

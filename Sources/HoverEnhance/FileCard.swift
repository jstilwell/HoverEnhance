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
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
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

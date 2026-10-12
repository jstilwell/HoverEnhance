import AppKit
import SwiftUI

/// The card shown beside a file or folder in Finder.
struct FileCardView: View {
    let card: FileCard
    /// Off beside a large preview of the file itself, which makes the thumbnail redundant.
    var showsImage = true
    var width: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // The same box for icon and thumbnail, so nothing moves when the thumbnail arrives.
                if showsImage {
                    Image(nsImage: card.thumbnail ?? card.icon)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: card.thumbnail == nil ? 0 : 4))
                        .frame(width: FileCard.imageSize, height: FileCard.imageSize)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name.showingHiddenCharacters).font(.headline).lineLimit(2)
                    if !card.kindAndSize.isEmpty {
                        Text(card.kindAndSize).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if card.options.shows(.path) {
                PathButton(card: card, text: card.formattedPath, id: FileCard.pathID, help: "Copy the path")
            }
            if let target = card.details.linkTarget {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.linkCaption(target)).font(.callout).foregroundStyle(.secondary)
                    if let text = card.formattedLinkTarget {
                        PathButton(card: card, text: text, id: FileCard.linkTargetID, help: "Copy where it points")
                    }
                }
            }
            DetailsGrid(card: card)
            if card.options.shows(.users) {
                UsersSection(card: card)
            }
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .task { await card.loadUsers() }
        .task { if showsImage { await card.loadThumbnail() } }
        .task { await card.loadSlowDetails() }
    }

    private static func linkCaption(_ target: FileDetails.LinkTarget) -> String {
        switch target {
        case .found: "Points to"
        case .missing(.some): "Points to an original that can't be found"
        case .missing(.none): "Its original can't be found"
        }
    }
}

/// Whichever details the file has. Clicking one copies it, when that's turned on.
private struct DetailsGrid: View {
    let card: FileCard

    var body: some View {
        let rows = card.rows
        if !rows.isEmpty {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.label).foregroundStyle(.secondary)
                        DetailValue(card: card, row: row)
                    }
                }
            }
            .font(.callout)
        }
    }
}

private struct DetailValue: View {
    let card: FileCard
    let row: DetailRow

    var body: some View {
        HStack(spacing: 4) {
            if card.options.copiesDetails, let copyText = row.copyText {
                Button { card.copy(copyText, id: row.id) } label: { text }
                    .buttonStyle(.plain)
                    .help("Copy")
            } else {
                text
            }
            if case .link(_, let url) = row.value {
                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.link)
                    .help(url.absoluteString)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Over the row rather than beside it, so nothing moves when it appears.
        .overlay(alignment: .trailing) {
            if card.copied == row.id {
                Image(systemName: "checkmark").foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    /// Finder's tag colors, by label number.
    private static func color(of tag: FileDetails.Tag) -> Color {
        switch tag.color {
        case 1: .gray
        case 2: .green
        case 3: .purple
        case 4: .blue
        case 5: .yellow
        case 6: .red
        case 7: .orange
        default: Color(white: 0.5).opacity(0.5)
        }
    }

    @ViewBuilder
    private var text: some View {
        switch row.value {
        case .text(let string):
            Text(string).lineLimit(1).truncationMode(.middle)
        case .link(let string, _):
            Text(string).lineLimit(1).truncationMode(.middle).foregroundStyle(.link)
        case .tags(let tags):
            HStack(spacing: 8) {
                ForEach(tags, id: \.name) { tag in
                    HStack(spacing: 4) {
                        Circle().fill(Self.color(of: tag)).frame(width: 9, height: 9)
                        Text(tag.name)
                    }
                }
            }
            .lineLimit(1)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking…").foregroundStyle(.secondary)
            }
        }
    }
}

/// A path in a box, which copies itself when clicked. Characters that would hide or rearrange part of
/// it are shown as codes; the copy is the real path.
private struct PathButton: View {
    let card: FileCard
    let text: String
    let id: String
    let help: String

    var body: some View {
        Button { card.copy(text, id: id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(text.showingHiddenCharacters)
                    .font(.system(.callout, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: card.copied == id ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(card.copied == id ? .green : .secondary)
                    .frame(width: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(card.copied == id ? "Copied" : help)
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

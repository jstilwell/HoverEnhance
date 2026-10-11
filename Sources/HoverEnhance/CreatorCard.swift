import SwiftUI

/// What the preview shows for a YouTube creator: who they are, and a way to their channel.
struct CreatorCardView: View {
    let channel: YouTubeChannel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: channel.avatar) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.title).font(.title3.weight(.semibold)).lineLimit(1)
                    if !details.isEmpty {
                        Text(details).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            if !channel.description.isEmpty {
                Text(channel.description)
                    .font(.callout)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Open Channel") { NSWorkspace.shared.open(channel.url) }
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
    }

    private var details: String {
        [channel.handle.map { "@\($0)" }, channel.subscribers, channel.videos].compactMap { $0 }.joined(separator: " · ")
    }
}

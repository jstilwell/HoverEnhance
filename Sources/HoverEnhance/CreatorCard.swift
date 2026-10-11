import SwiftUI

/// What the preview shows for a YouTube creator: who they are, a way to their channel, and
/// subscribing when signed in.
struct CreatorCardView: View {
    let channel: YouTubeChannel
    @State private var subscription: Subscription

    init(channel: YouTubeChannel) {
        self.channel = channel
        _subscription = State(initialValue: Subscription(channelID: channel.id))
    }

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
                SubscribeButton(subscription: subscription)
                Button("Open Channel") { NSWorkspace.shared.open(channel.url) }
                Spacer()
            }
            if let error = subscription.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1).help(error)
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .task { await subscription.load() }
    }

    private var details: String {
        [channel.handle.map { "@\($0)" }, channel.subscribers, channel.videos].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct SubscribeButton: View {
    let subscription: Subscription

    var body: some View {
        switch subscription.status {
        case .signedOut:
            Button("Sign In to Subscribe…") {
                NotificationCenter.default.post(name: .showSettingsTab, object: "Accounts")
            }
        case .checking, .changing:
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(subscription.status == .checking ? "Subscribe" : "Updating…")
                }
            }
            .disabled(true)
        case .notSubscribed:
            Button("Subscribe") { Task { await subscription.toggle() } }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        case .subscribed:
            Label("Subscribed", systemImage: "checkmark").foregroundStyle(.secondary)
            Button("Unsubscribe") { Task { await subscription.toggle() } }
        }
    }
}

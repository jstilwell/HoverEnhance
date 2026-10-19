import AppKit
import SwiftUI

/// What the preview shows for a YouTube link on YouTube, in YouTube's own look: for a video, the video
/// and then who made it; for a channel, its page header. Subscribing works when signed in.
struct CreatorCardView: View {
    let channel: YouTubeChannel
    let video: YouTubeVideo?
    @State private var subscription: Subscription

    static let width: CGFloat = 440

    init(channel: YouTubeChannel, video: YouTubeVideo? = nil) {
        self.channel = channel
        self.video = video
        _subscription = State(initialValue: Subscription(channelID: channel.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let video {
                VideoSection(video: video)
                HStack(spacing: 12) {
                    Button { NSWorkspace.shared.open(channel.url) } label: {
                        HStack(spacing: 12) {
                            Avatar(url: channel.avatar, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                ChannelName(channel: channel, size: 15)
                                if let subscribers = channel.subscribers {
                                    Text(subscribers).font(.system(size: 12)).foregroundStyle(YouTubeTheme.secondary).lineLimit(1)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .help("Open \(channel.title)'s channel")
                    Spacer(minLength: 4)
                    SubscribeButton(subscription: subscription)
                    if let likes = video.likes {
                        Label(YouTubeFormat.count(likes), systemImage: "hand.thumbsup")
                            .font(.system(size: 13, weight: .medium))
                            .pill(YouTubeTheme.tonal)
                            .accessibilityLabel("\(likes.formatted()) likes")
                    }
                }
                AboutBox(video: video)
            } else {
                ChannelHeader(channel: channel, subscription: subscription)
            }
            if let error = subscription.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1).help(error)
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .foregroundStyle(YouTubeTheme.text)
        .background(YouTubeTheme.background, in: RoundedRectangle(cornerRadius: PreviewPanel.cornerRadius - PreviewGeometry.padding))
        .task { await subscription.load() }
    }
}

/// The video's thumbnail, with its length or LIVE, and its title.
private struct VideoSection: View {
    let video: YouTubeVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: video.thumbnail) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                YouTubeTheme.tonal
            }
            .frame(width: CreatorCardView.width - 28, height: ((CreatorCardView.width - 28) * 9 / 16).rounded())
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomTrailing) {
                if video.isLive {
                    Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                        .cornerBadge(Color(red: 0.8, green: 0, blue: 0))
                } else if let length = video.length {
                    Text(YouTubeFormat.length(length)).cornerBadge(Color.black.opacity(0.8))
                }
            }
            Text(video.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// YouTube's gray box under a video: views, when, and its category, over the start of its description.
private struct AboutBox: View {
    let video: YouTubeVideo

    var body: some View {
        let facts = [video.views.map(YouTubeFormat.views), video.published.map(YouTubeFormat.age), video.category].compactMap { $0 }
        if !facts.isEmpty || !video.description.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !facts.isEmpty {
                    Text(facts.joined(separator: "  ")).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                if !video.description.isEmpty {
                    Text(video.description)
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(YouTubeTheme.tonal, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// A channel's banner, avatar, name, numbers, description, and buttons, as at the top of its page.
private struct ChannelHeader: View {
    let channel: YouTubeChannel
    let subscription: Subscription

    var body: some View {
        if let banner = channel.banner {
            AsyncImage(url: banner) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                YouTubeTheme.tonal
            }
            // YouTube's banners are cropped to about 6.2:1 on the channel page.
            .frame(width: CreatorCardView.width - 28, height: ((CreatorCardView.width - 28) / 6.2).rounded())
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        HStack(alignment: .top, spacing: 14) {
            Avatar(url: channel.avatar, size: 80)
            VStack(alignment: .leading, spacing: 4) {
                ChannelName(channel: channel, size: 20)
                if !details.isEmpty {
                    Text(details).font(.system(size: 13)).foregroundStyle(YouTubeTheme.secondary).lineLimit(2)
                }
                if !channel.description.isEmpty {
                    Text(channel.description)
                        .font(.system(size: 13))
                        .foregroundStyle(YouTubeTheme.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    SubscribeButton(subscription: subscription)
                    Button("View channel") { NSWorkspace.shared.open(channel.url) }
                        .font(.system(size: 13, weight: .medium))
                        .pill(YouTubeTheme.tonal)
                }
                .padding(.top, 6)
            }
        }
    }

    private var details: String {
        [channel.handle.map { "@\($0)" }, channel.subscribers, channel.videos].compactMap { $0 }.joined(separator: " • ")
    }
}

private struct ChannelName: View {
    let channel: YouTubeChannel
    let size: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Text(channel.title).font(.system(size: size, weight: size > 16 ? .bold : .semibold)).lineLimit(1)
            if channel.isVerified {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(YouTubeTheme.secondary)
                    .accessibilityLabel("Verified")
            }
        }
    }
}

private struct Avatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(YouTubeTheme.tonal)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct SubscribeButton: View {
    let subscription: Subscription
    /// Unsubscribing takes a second click, as on YouTube, which asks first.
    @State private var confirming = false

    var body: some View {
        Group {
            switch subscription.status {
            case .signedOut:
                // As on YouTube, Subscribe asks you to sign in first.
                Button("Subscribe") { NotificationCenter.default.post(name: .showSettingsTab, object: SettingsTab.accounts) }
                    .pill(YouTubeTheme.text, text: YouTubeTheme.background)
                    .help("Sign in to YouTube in Settings to subscribe")
            case .apiOff(let fix):
                Button("Turn On YouTube API…") { NSWorkspace.shared.open(fix) }.pill(YouTubeTheme.tonal)
            case .checking, .changing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(subscription.status == .checking ? "Subscribe" : "Updating…")
                }
                .pill(YouTubeTheme.tonal)
                .foregroundStyle(YouTubeTheme.secondary)
            case .notSubscribed:
                Button("Subscribe") { Task { await subscription.toggle() } }
                    .pill(YouTubeTheme.text, text: YouTubeTheme.background)
            case .subscribed:
                if confirming {
                    Button("Unsubscribe") {
                        confirming = false
                        Task { await subscription.toggle() }
                    }
                    .pill(YouTubeTheme.tonal, text: .red)
                } else {
                    Button {
                        confirming = true
                        Task {
                            try? await Task.sleep(for: .seconds(4))
                            confirming = false
                        }
                    } label: {
                        Label("Subscribed", systemImage: "bell")
                    }
                    .pill(YouTubeTheme.tonal)
                    .help("Click again to unsubscribe")
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
        .fixedSize()
    }
}

private extension View {
    /// YouTube's rounded buttons and chips.
    func pill(_ fill: Color, text: Color = YouTubeTheme.text) -> some View {
        padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(text)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
    }

    /// A label over the corner of a thumbnail, like a video's length.
    func cornerBadge(_ fill: Color) -> some View {
        font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 4))
            .padding(8)
    }
}

/// YouTube's colors, light and dark.
enum YouTubeTheme {
    static let background = Color(light: 0xFFFFFF, dark: 0x0F0F0F)
    static let text = Color(light: 0x0F0F0F, dark: 0xF1F1F1)
    static let secondary = Color(light: 0x606060, dark: 0xAAAAAA)
    /// Buttons and boxes that aren't the main action.
    static let tonal = Color(light: 0xF2F2F2, dark: 0x272727)
}

/// Counts, dates, and lengths the way YouTube writes them.
enum YouTubeFormat {
    /// "630", "37K", "1.6M".
    static func count(_ number: Int, locale: Locale = .current) -> String {
        number.formatted(.number.notation(.compactName).locale(locale))
    }

    static func views(_ number: Int) -> String {
        number == 1 ? "1 view" : "\(count(number)) views"
    }

    /// "3 years ago".
    static func age(_ date: Date) -> String {
        age(date, relativeTo: .now)
    }

    static func age(_ date: Date, relativeTo now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    static func length(_ seconds: Int) -> String {
        VideoPlayback.clock(Double(seconds))
    }
}

extension Color {
    /// One color in light mode and another in dark, from hex RGB.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

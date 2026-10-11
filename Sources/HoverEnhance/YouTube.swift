import Foundation

/// A YouTube channel, as the creator card shows it.
struct YouTubeChannel: Sendable, Equatable {
    /// The channel ID, "UC…".
    let id: String
    let title: String
    /// Without the "@".
    let handle: String?
    let description: String
    let avatar: URL?
    /// Display text, like "4.55M subscribers". Missing when the channel hides its count.
    let subscribers: String?
    /// Display text, like "437 videos".
    let videos: String?

    var url: URL {
        URL(string: handle.map { "https://www.youtube.com/@\($0)" } ?? "https://www.youtube.com/channel/\(id)")!
    }
}

/// A link that leads to a YouTube channel: directly, or through one of its videos.
enum YouTubeChannelRef: Sendable, Hashable {
    /// The creator of a video.
    case video(String)
    /// A handle, without the "@".
    case handle(String)
    /// A channel ID, "UC…".
    case id(String)
    /// An old-style /c/<name> or /user/<name> path.
    case legacyPath(String)
}

enum YouTube {
    static func isYouTube(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }

    static func channelRef(fromLink url: URL) -> YouTubeChannelRef? {
        guard isYouTube(url) else { return nil }
        if let embed = Embed.from(link: url), embed.site == .youtube {
            return .video(embed.id)
        }
        let parts = Array(url.pathComponents.dropFirst())
        guard let first = parts.first else { return nil }
        if first.hasPrefix("@"), first.count > 1 {
            return .handle(String(first.dropFirst()))
        }
        if first == "channel", parts.count > 1, parts[1].hasPrefix("UC") {
            return .id(parts[1])
        }
        if ["c", "user"].contains(first), parts.count > 1 {
            return .legacyPath("/\(first)/\(parts[1])")
        }
        return nil
    }

    // MARK: - Public pages

    /// YouTube's oEmbed endpoint names a video's creator, with a link to their channel.
    static func oEmbedURL(videoID: String) -> URL {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url!
    }

    static func channelPageURL(fromOEmbed data: Data) -> URL? {
        struct OEmbed: Decodable { let author_url: String }
        return (try? JSONDecoder().decode(OEmbed.self, from: data)).flatMap { URL(string: $0.author_url) }
    }

    static func channelPageURL(for ref: YouTubeChannelRef) -> URL? {
        switch ref {
        case .video: nil
        case .handle(let handle): URL(string: "https://www.youtube.com/@\(handle)")
        case .id(let id): URL(string: "https://www.youtube.com/channel/\(id)")
        case .legacyPath(let path): URL(string: "https://www.youtube.com\(path)")
        }
    }

    /// Reads a channel from its page, which embeds the channel's data as `ytInitialData`.
    static func channel(inPage html: String) -> YouTubeChannel? {
        guard let data = initialData(inPage: html),
              let meta = (data["metadata"] as? [String: Any])?["channelMetadataRenderer"] as? [String: Any],
              let id = meta["externalId"] as? String, let title = meta["title"] as? String else { return nil }

        let avatar = ((meta["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
        let handle = (meta["vanityChannelUrl"] as? String).flatMap(URL.init(string:))?.lastPathComponent
            .replacingOccurrences(of: "@", with: "")
        // The counts are display strings somewhere in the page header.
        let headerTexts = strings(in: data["header"] ?? [:])
        return YouTubeChannel(
            id: id,
            title: title,
            handle: handle?.isEmpty == false ? handle : nil,
            description: (meta["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            avatar: avatar.flatMap(URL.init(string:)),
            subscribers: headerTexts.first { $0.hasSuffix(" subscribers") || $0.hasSuffix(" subscriber") },
            videos: headerTexts.first { $0.hasSuffix(" videos") || $0.hasSuffix(" video") }
        )
    }

    /// `ytInitialData` is either a JSON object literal or a JavaScript string holding the JSON.
    static func initialData(inPage html: String) -> [String: Any]? {
        guard let marker = html.range(of: "var ytInitialData = ") else { return nil }
        let rest = html[marker.upperBound...]
        let json: String
        if rest.first == "'" {
            guard let decoded = javaScriptString(atStartOf: rest) else { return nil }
            json = decoded
        } else {
            guard let end = rest.range(of: ";</script>") else { return nil }
            json = String(rest[..<end.lowerBound])
        }
        return try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }

    /// Decodes the single-quoted JavaScript string literal that `text` starts with.
    static func javaScriptString(atStartOf text: Substring) -> String? {
        var scalars = text.unicodeScalars.makeIterator()
        guard scalars.next() == "'" else { return nil }
        var result = String.UnicodeScalarView()

        func hex(_ count: Int) -> Unicode.Scalar? {
            var digits = ""
            for _ in 0..<count { guard let next = scalars.next() else { return nil }; digits.unicodeScalars.append(next) }
            return UInt32(digits, radix: 16).flatMap(Unicode.Scalar.init)
        }

        while let scalar = scalars.next() {
            switch scalar {
            case "'":
                return String(result)
            case "\\":
                guard let escaped = scalars.next() else { return nil }
                switch escaped {
                case "x": guard let value = hex(2) else { return nil }; result.append(value)
                case "u": guard let value = hex(4) else { return nil }; result.append(value)
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "b": result.append("\u{8}")
                case "f": result.append("\u{C}")
                case "v": result.append("\u{B}")
                case "0": result.append("\u{0}")
                default: result.append(escaped)
                }
            default:
                result.append(scalar)
            }
        }
        return nil
    }

    /// Every string in a JSON value, depth first.
    private static func strings(in value: Any) -> [String] {
        switch value {
        case let string as String: [string]
        case let array as [Any]: array.flatMap(strings)
        case let object as [String: Any]: object.keys.sorted().flatMap { strings(in: object[$0]!) }
        default: []
        }
    }
}

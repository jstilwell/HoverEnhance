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
    /// The wide image across the top of the channel's page.
    var banner: URL? = nil
    var isVerified = false

    var url: URL {
        URL(string: handle.map { "https://www.youtube.com/@\($0)" } ?? "https://www.youtube.com/channel/\(id)")!
    }
}

/// A YouTube video, as the card for a link to it shows it.
struct YouTubeVideo: Sendable, Equatable {
    let id: String
    let title: String
    /// Seconds. Missing for live streams.
    let length: Int?
    let isLive: Bool
    let views: Int?
    /// Missing when the uploader hides ratings. YouTube shows no one dislikes but the uploader.
    let likes: Int?
    let published: Date?
    /// Like "Science & Technology".
    let category: String?
    let description: String
    let thumbnail: URL?
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

    static func watchPageURL(videoID: String) -> URL {
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components.url!
    }

    /// Reads a video from its watch page, which embeds it as `ytInitialPlayerResponse`, with the address
    /// of its channel's page.
    static func video(inPage html: String) -> (video: YouTubeVideo, channelPage: URL?)? {
        guard let response = object(named: "ytInitialPlayerResponse", inPage: html),
              let details = response["videoDetails"] as? [String: Any],
              let id = details["videoId"] as? String, let title = details["title"] as? String else { return nil }
        // The microformat is what YouTube gives search engines: plain numbers and dates.
        let micro = value(in: response, "microformat", "playerMicroformatRenderer") as? [String: Any] ?? [:]
        func number(_ value: Any?) -> Int? { (value as? String).flatMap { Int($0) } ?? value as? Int }
        let thumbnails = (value(in: micro, "thumbnail", "thumbnails") ?? value(in: details, "thumbnail", "thumbnails")) as? [[String: Any]] ?? []
        let channelID = (details["channelId"] as? String).flatMap { isChannelID($0) ? $0 : nil }
        let video = YouTubeVideo(
            id: id,
            title: title,
            length: number(details["lengthSeconds"]).flatMap { $0 > 0 ? $0 : nil },
            isLive: details["isLive"] as? Bool ?? false,
            views: number(details["viewCount"]) ?? number(micro["viewCount"]),
            likes: details["allowRatings"] as? Bool == false ? nil : number(micro["likeCount"]),
            published: (micro["publishDate"] as? String).flatMap(date),
            category: micro["category"] as? String,
            description: (details["shortDescription"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            thumbnail: largest(thumbnails)
        )
        return (video, channelID.flatMap { URL(string: "https://www.youtube.com/channel/\($0)") })
    }

    /// "UC" and 22 more letters, digits, `-`, or `_`, so it's safe in an address.
    private static func isChannelID(_ string: String) -> Bool {
        string.count == 24 && string.hasPrefix("UC") && string.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// "2023-06-29T23:52:58-07:00", or a date alone on older pages.
    private static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)
    }

    /// The widest of a list of `{url, width}` images, or the first at least `width` wide, from the web.
    private static func largest(_ images: [[String: Any]], atLeast width: Int? = nil) -> URL? {
        let sized = images.compactMap { image -> (url: URL, width: Int)? in
            guard let url = (image["url"] as? String).flatMap(URL.init(string:)), url.scheme == "https", !LocalNetwork.contains(url) else { return nil }
            return (url, image["width"] as? Int ?? 0)
        }.sorted { $0.width < $1.width }
        if let width, let fit = sized.first(where: { $0.width >= width }) { return fit.url }
        return sized.last?.url
    }

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
        let header = value(in: data, "header", "pageHeaderRenderer", "content", "pageHeaderViewModel") as? [String: Any]
        let banners = value(in: header, "banner", "imageBannerViewModel", "image", "sources") as? [[String: Any]] ?? []
        let handle = (meta["vanityChannelUrl"] as? String).flatMap(URL.init(string:))?.lastPathComponent
            .replacingOccurrences(of: "@", with: "")
        // The counts are display strings somewhere in the page header, each also spelled out for
        // VoiceOver ("1.64 million subscribers"); the short one is what the page shows.
        let headerTexts = strings(in: data["header"] ?? [:])
        return YouTubeChannel(
            id: id,
            title: title,
            handle: handle?.isEmpty == false ? handle : nil,
            description: (meta["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            avatar: avatar.flatMap(URL.init(string:)),
            subscribers: shortest(headerTexts) { $0.hasSuffix(" subscribers") || $0.hasSuffix(" subscriber") },
            videos: shortest(headerTexts) { $0.hasSuffix(" videos") || $0.hasSuffix(" video") },
            // Wide enough for the card on a Retina display.
            banner: largest(banners, atLeast: 900),
            // The check after the name is an icon in its text.
            isVerified: strings(in: header?["title"] ?? [:]).contains { $0.hasPrefix("CHECK_CIRCLE") }
        )
    }

    static func initialData(inPage html: String) -> [String: Any]? {
        object(named: "ytInitialData", inPage: html)
    }

    /// `var <name> = …` in a page: either a JSON object literal or a JavaScript string holding the JSON.
    static func object(named name: String, inPage html: String) -> [String: Any]? {
        guard let marker = html.range(of: "var \(name) = ") else { return nil }
        let rest = html[marker.upperBound...]
        let json: String
        if rest.first == "'" {
            guard let decoded = javaScriptString(atStartOf: rest) else { return nil }
            json = decoded
        } else {
            guard let literal = objectLiteral(atStartOf: rest) else { return nil }
            json = String(literal)
        }
        return try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }

    /// The JSON object `text` starts with, through its closing brace: more script can follow it.
    static func objectLiteral(atStartOf text: Substring) -> Substring? {
        guard text.first == "{" else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in text.utf8.indices {
            let byte = text.utf8[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { return text[...index] }
            }
        }
        return nil
    }

    /// What's at `path` in nested JSON objects.
    private static func value(in object: Any?, _ path: String...) -> Any? {
        path.reduce(object) { ($0 as? [String: Any])?[$1] }
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

    private static func shortest(_ strings: [String], where matches: (String) -> Bool) -> String? {
        strings.filter(matches).min { $0.count < $1.count }
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

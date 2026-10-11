import Foundation

/// A video on a site that doesn't offer a stream other players can use, shown through the site's
/// own embeddable player in a web view.
struct Embed: Sendable, Hashable {
    enum Site: Sendable, Hashable {
        case youtube, vimeo, tiktok, twitch

        /// Pages on these domains have their own hover previews, so links there are left alone.
        var domains: [String] {
            switch self {
            case .youtube: ["youtube.com", "youtu.be"]
            case .vimeo: ["vimeo.com"]
            case .tiktok: ["tiktok.com"]
            case .twitch: ["twitch.tv"]
            }
        }
    }

    let site: Site
    let id: String
    /// Seconds in, from links like youtube.com/watch?v=…&t=90.
    var start: Int?
    /// Vimeo's key for unlisted videos (vimeo.com/<id>/<hash>).
    var hash: String?
    /// YouTube Shorts and TikToks are portrait.
    var isPortrait = false

    /// The page origin the players are embedded under. YouTube won't play without a Referer (its
    /// "error 153"), and Twitch checks its `parent` parameter against this host.
    static let origin = URL(string: "https://\((Bundle.main.bundleIdentifier ?? "hoverenhance").lowercased())/")!

    var size: CGSize {
        isPortrait ? CGSize(width: 405, height: 720) : CGSize(width: 960, height: 540)
    }

    func playerURL(muted: Bool) -> URL? {
        let mute = muted ? "1" : "0"
        let string = switch site {
        case .youtube:
            "https://www.youtube.com/embed/\(id)?autoplay=1&mute=\(mute)&playsinline=1&rel=0" + (start.map { "&start=\($0)" } ?? "")
        case .vimeo:
            "https://player.vimeo.com/video/\(id)?autoplay=1&muted=\(mute)" + (hash.map { "&h=\($0)" } ?? "") + (start.map { "#t=\($0)s" } ?? "")
        case .tiktok:
            "https://www.tiktok.com/player/v1/\(id)?autoplay=1&loop=1&muted=\(mute)"
        case .twitch:
            "https://clips.twitch.tv/embed?clip=\(id)&parent=\(Self.origin.host() ?? "")&autoplay=true&muted=\(muted)"
        }
        return URL(string: string)
    }

    /// Links to videos these players can show.
    static func from(link url: URL) -> Embed? {
        guard let host = url.host()?.lowercased() else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let start = query.first { $0.name == "t" || $0.name == "start" }?.value.flatMap(seconds)

        switch host {
        case "youtu.be":
            return parts.first.flatMap { youtube($0, start: start) }
        case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
            switch parts.first {
            case "watch": return query.first { $0.name == "v" }?.value.flatMap { youtube($0, start: start) }
            case "shorts": return parts.count > 1 ? youtube(parts[1], start: nil, portrait: true) : nil
            case "embed", "live": return parts.count > 1 ? youtube(parts[1], start: start) : nil
            default: return nil
            }
        case "vimeo.com", "www.vimeo.com", "player.vimeo.com":
            // vimeo.com/<id>[/<hash>], vimeo.com/channels/<name>/<id>, player.vimeo.com/video/<id>
            guard let index = parts.firstIndex(where: { !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
            let hash = parts.indices.contains(index + 1) ? parts[index + 1] : query.first { $0.name == "h" }?.value
            return Embed(site: .vimeo, id: parts[index], start: start, hash: hash.flatMap(slug))
        case "tiktok.com", "www.tiktok.com", "m.tiktok.com":
            // @<user>/video/<id>
            guard parts.count >= 3, parts[1] == "video", parts[2].allSatisfy(\.isNumber) else { return nil }
            return Embed(site: .tiktok, id: parts[2], isPortrait: true)
        case "clips.twitch.tv":
            return parts.first.flatMap(slug).map { Embed(site: .twitch, id: $0) }
        case "twitch.tv", "www.twitch.tv", "m.twitch.tv":
            // <channel>/clip/<slug>
            guard parts.count >= 3, parts[1] == "clip" else { return nil }
            return slug(parts[2]).map { Embed(site: .twitch, id: $0) }
        default:
            return nil
        }
    }

    private static func youtube(_ id: String, start: Int?, portrait: Bool = false) -> Embed? {
        guard id.count == 11, slug(id) != nil else { return nil }
        return Embed(site: .youtube, id: id, start: start, isPortrait: portrait)
    }

    /// Letters, digits, `-`, and `_`.
    private static func slug(_ string: String) -> String? {
        let valid = !string.isEmpty && string.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return valid ? string : nil
    }

    /// "90", "90s", "1m30s", "1h2m3s" → seconds.
    private static func seconds(_ string: String) -> Int? {
        if let plain = Int(string) { return plain }
        var total = 0
        var number = ""
        for character in string {
            if character.isNumber {
                number.append(character)
            } else {
                guard let value = Int(number) else { return nil }
                switch character {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: return nil
                }
                number = ""
            }
        }
        return number.isEmpty ? total : nil
    }
}

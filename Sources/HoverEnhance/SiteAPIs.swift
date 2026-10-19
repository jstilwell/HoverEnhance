import Foundation

/// Requests and response parsing for the public APIs behind `MediaSource` lookups.
enum SiteAPIs {
    // MARK: - Streamable

    static func streamableURL(id: String) -> URL {
        URL(string: "https://api.streamable.com/videos/\(id)")!
    }

    static func streamable(_ data: Data) -> Media? {
        struct Video: Decodable {
            struct File: Decodable { let url: String?; let width: Double?; let height: Double? }
            let files: [String: File]
        }
        guard let video = try? JSONDecoder().decode(Video.self, from: data) else { return nil }
        // "original" is often missing a URL; "mp4" is the full-quality rendition.
        for name in ["mp4", "mp4-mobile"] {
            guard let file = video.files[name], let string = file.url,
                  let url = URL(string: string.hasPrefix("//") ? "https:" + string : string) else { continue }
            return Media(items: [.video(url, size: size(file.width, file.height))])
        }
        return nil
    }

    // MARK: - RedGIFs

    /// A token for RedGIFs' API, which it hands out to anyone. It lasts a day, and only for the address
    /// and user agent that asked for it.
    static let redgifsTokenURL = URL(string: "https://api.redgifs.com/v2/auth/temporary")!

    static func redgifsToken(_ data: Data) -> String? {
        struct Token: Decodable { let token: String }
        return (try? JSONDecoder().decode(Token.self, from: data))?.token
    }

    static func redgifsGifURL(id: String) -> URL {
        URL(string: "https://api.redgifs.com/v2/gifs/\(id)")!
    }

    static func redgifsGalleryURL(id: String) -> URL? {
        guard id.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == "-") }) else { return nil }
        return URL(string: "https://api.redgifs.com/v2/gallery/\(id)")
    }

    private struct RedgifsGif: Decodable {
        struct URLs: Decodable { let hd: String?; let sd: String? }
        /// 1 for a video, 2 for an image.
        let type: Int?
        let width: Double?
        let height: Double?
        let urls: URLs
        let gallery: String?

        var item: MediaItem? {
            let urls = [urls.hd, urls.sd].compactMap { $0.flatMap(URL.init(string:)) }
            guard let best = urls.first else { return nil }
            return type == 2 ? .image(urls) : .video(best, size: SiteAPIs.size(width, height))
        }
    }

    /// One gif's video or image, and the id of the gallery it's in, if any.
    static func redgifsGif(_ data: Data) -> (media: Media, gallery: String?)? {
        struct Response: Decodable { let gif: RedgifsGif }
        guard let gif = (try? JSONDecoder().decode(Response.self, from: data))?.gif, let item = gif.item else { return nil }
        return (Media(items: [item]), gif.gallery)
    }

    static func redgifsGallery(_ data: Data) -> Media? {
        struct Response: Decodable { let gifs: [RedgifsGif] }
        let items = (try? JSONDecoder().decode(Response.self, from: data))?.gifs.compactMap(\.item) ?? []
        return items.isEmpty ? nil : Media(items: items)
    }

    // MARK: - Erome

    static func eromeAlbumURL(_ album: String) -> URL {
        URL(string: "https://www.erome.com/a/\(album)")!
    }

    /// The album page puts each photo or video in a `media-group`: a video's `<source>`s, best last, or
    /// a photo's full-size `data-src`.
    static func erome(albumPage html: String) -> Media? {
        let items = html.components(separatedBy: #"class="media-group""#).dropFirst().compactMap { group -> MediaItem? in
            let sources = group.matches(of: /<source ([^>]*)>/).compactMap { tag -> (url: String, res: Int)? in
                guard let src = tag.1.firstMatch(of: /src="([^"]+)"/) else { return nil }
                return (String(src.1), tag.1.firstMatch(of: /res='(\d+)'/).flatMap { Int($0.1) } ?? 0)
            }
            if let best = sources.max(by: { $0.res < $1.res }), let url = URL(string: best.url) {
                return .video(url, size: nil)
            }
            return group.firstMatch(of: /class="img" data-src="([^"]+)"/).flatMap { URL(string: String($0.1)) }.map { .image([$0]) }
        }
        return items.isEmpty ? nil : Media(items: items)
    }

    // MARK: - X (Twitter)

    /// The endpoint X's own embedded tweets use. It needs no account.
    static func tweetURL(id: String) -> URL {
        URL(string: "https://cdn.syndication.twimg.com/tweet-result?id=\(id)&token=\(syndicationToken(id))")!
    }

    /// The `token` embedders send alongside the id: π·id/10¹⁵ in base 36, without zeros or the point.
    static func syndicationToken(_ id: String) -> String {
        // Ids are 64-bit; anything else would overflow the whole part below.
        guard let number = Double(id), number >= 0, number < 1e20 else { return "0" }
        let value = number / 1e15 * Double.pi
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var whole = Int(value)
        var fraction = value - Double(whole)
        var token = ""
        repeat {
            token.insert(digits[whole % 36], at: token.startIndex)
            whole /= 36
        } while whole > 0
        for _ in 0..<10 {
            fraction *= 36
            let digit = Int(fraction)
            token.append(digits[digit])
            fraction -= Double(digit)
        }
        return token.replacingOccurrences(of: "0", with: "")
    }

    static func tweet(_ data: Data) -> Media? {
        struct Tweet: Decodable {
            struct Size: Decodable { let width: Double; let height: Double }
            struct Variant: Decodable { let content_type: String; let url: String; let bitrate: Int? }
            struct VideoInfo: Decodable { let variants: [Variant] }
            struct Attachment: Decodable {
                let type: String
                let media_url_https: String
                let original_info: Size?
                let video_info: VideoInfo?
            }
            let mediaDetails: [Attachment]?
        }
        guard let tweet = try? JSONDecoder().decode(Tweet.self, from: data) else { return nil }
        let items = (tweet.mediaDetails ?? []).compactMap { media -> MediaItem? in
            let size = media.original_info.map { CGSize(width: $0.width, height: $0.height) }
            if let variants = media.video_info?.variants {
                // Highest-bitrate MP4; GIFs come as a single MP4 too.
                let best = variants.filter { $0.content_type == "video/mp4" }.max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
                return best.flatMap { URL(string: $0.url) }.map { .video($0, size: size) }
            }
            guard let image = URL(string: media.media_url_https) else { return nil }
            // name=orig asks pbs.twimg.com for the uploaded size.
            let original = URL(string: media.media_url_https + "?name=orig")
            return .image([original, image].compactMap { $0 })
        }
        return items.isEmpty ? nil : Media(items: items)
    }

    // MARK: - Bluesky

    static func blueskyHandleURL(_ handle: String) -> URL? {
        var components = URLComponents(string: "https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle")
        components?.queryItems = [URLQueryItem(name: "handle", value: handle)]
        return components?.url
    }

    static func blueskyDID(_ data: Data) -> String? {
        struct Resolved: Decodable { let did: String }
        return (try? JSONDecoder().decode(Resolved.self, from: data))?.did
    }

    /// Bluesky's public AppView wants the post's AT URI with a DID, not a handle.
    static func blueskyPostURL(did: String, rkey: String) -> URL? {
        var components = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.feed.getPosts")
        components?.queryItems = [URLQueryItem(name: "uris", value: "at://\(did)/app.bsky.feed.post/\(rkey)")]
        return components?.url
    }

    static func blueskyPost(_ data: Data) -> Media? {
        struct Response: Decodable { let posts: [Post] }
        struct Post: Decodable { let embed: Embed? }
        struct AspectRatio: Decodable { let width: Double; let height: Double }
        struct Image: Decodable { let fullsize: String; let thumb: String? }
        final class Embed: Decodable {
            let images: [Image]?
            let playlist: String?
            let aspectRatio: AspectRatio?
            /// Set on posts that quote another post and carry their own media.
            let media: Embed?
        }
        guard let embed = (try? JSONDecoder().decode(Response.self, from: data))?.posts.first?.embed else { return nil }
        let media = embed.media ?? embed
        if let playlist = media.playlist.flatMap(URL.init(string:)) {
            return Media(items: [.video(playlist, size: media.aspectRatio.flatMap { size($0.width, $0.height) })])
        }
        let items = (media.images ?? []).map { image in
            MediaItem.image([image.fullsize, image.thumb].compactMap { $0.flatMap(URL.init(string:)) })
        }
        return items.isEmpty ? nil : Media(items: items)
    }

    // MARK: - Instagram

    static func instagramEmbedURL(code: String) -> URL {
        URL(string: "https://www.instagram.com/p/\(code)/embed/")!
    }

    /// The post's full-size image (for a reel, its cover), served without the embed page. Works
    /// even when the owner has turned embedding off.
    static func instagramImageURL(code: String) -> URL {
        URL(string: "https://www.instagram.com/p/\(code)/media/?size=l")!
    }

    /// Instagram's embed page carries the post as JSON inside a JSON string ("contextJSON"). When
    /// the owner has turned embedding off the page holds an error instead, and this returns nil.
    static func instagram(embedPage html: String) -> Media? {
        guard let key = html.range(of: "\"contextJSON\":"),
              let json = jsonString(atStartOf: html[key.upperBound...]),
              let context = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let post = (context["gql_data"] as? [String: Any])?["shortcode_media"] as? [String: Any] else { return nil }

        // Posts with several photos or videos list them as children.
        let children = ((post["edge_sidecar_to_children"] as? [String: Any])?["edges"] as? [[String: Any]])?
            .compactMap { $0["node"] as? [String: Any] }
        let items = (children ?? [post]).compactMap { node -> MediaItem? in
            if node["is_video"] as? Bool == true, let video = (node["video_url"] as? String).flatMap(URL.init(string:)) {
                return .video(video, size: nil)
            }
            return (node["display_url"] as? String).flatMap(URL.init(string:)).map { .image([$0]) }
        }
        return items.isEmpty ? nil : Media(items: items)
    }

    /// Decodes the JSON string literal that `text` starts with (after optional whitespace).
    private static func jsonString(atStartOf text: Substring) -> String? {
        let bytes = text.utf8.drop { $0 == UInt8(ascii: " ") }
        guard bytes.first == UInt8(ascii: "\"") else { return nil }
        var escaped = false
        for index in bytes.indices.dropFirst() {
            let byte = bytes[index]
            if escaped {
                escaped = false
            } else if byte == UInt8(ascii: "\\") {
                escaped = true
            } else if byte == UInt8(ascii: "\"") {
                return try? JSONDecoder().decode(String.self, from: Data(bytes[bytes.startIndex...index]))
            }
        }
        return nil
    }

    private static func size(_ width: Double?, _ height: Double?) -> CGSize? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}

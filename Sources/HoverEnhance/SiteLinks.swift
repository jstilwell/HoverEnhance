import Foundation

/// Links to posts and videos whose media needs a lookup or plays as video.
enum SiteLinks {
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "m3u8"]

    private static let xHosts: Set<String> = [
        "x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com",
        "fxtwitter.com", "vxtwitter.com", "fixupx.com",
    ]

    static func source(forLink url: URL) -> MediaSource? {
        guard ImageRules.isFetchable(url), let host = url.host()?.lowercased() else { return nil }
        if videoExtensions.contains(url.pathExtension.lowercased()) {
            return .video(url)
        }
        if let id = RedditGallery.id(fromLink: url) {
            return .redditGallery(id: id)
        }

        let parts = url.pathComponents
        switch host {
        case "v.redd.it":
            // v.redd.it/<id> is a Reddit-hosted video, served as HLS.
            guard parts.count >= 2, isAlphanumeric(parts[1]) else { return nil }
            return URL(string: "https://v.redd.it/\(parts[1])/HLSPlaylist.m3u8").map(MediaSource.video)

        case "streamable.com", "www.streamable.com":
            // streamable.com/<id>, or /e/<id> and /o/<id> for embeds.
            let id = parts.count == 2 ? parts[1] : (parts.count == 3 && ["e", "o", "s"].contains(parts[1]) ? parts[2] : nil)
            guard let id, isAlphanumeric(id) else { return nil }
            return .streamable(id: id)

        case _ where xHosts.contains(host):
            // <user>/status/<id>, optionally followed by /photo/1 or /video/1.
            guard parts.count >= 4, parts[2] == "status", parts[3].allSatisfy(\.isNumber) else { return nil }
            return .tweet(id: parts[3])

        case "bsky.app":
            // profile/<handle or DID>/post/<rkey>
            guard parts.count >= 5, parts[1] == "profile", parts[3] == "post" else { return nil }
            return .blueskyPost(actor: parts[2], rkey: parts[4])

        case "i.imgur.com":
            // .gifv is a web page around an MP4 of the same name.
            guard url.pathExtension.lowercased() == "gifv" else { return nil }
            return URL(string: "https://i.imgur.com/\(url.deletingPathExtension().lastPathComponent).mp4").map(MediaSource.video)

        default:
            return nil
        }
    }

    private static func isAlphanumeric(_ string: String) -> Bool {
        !string.isEmpty && string.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

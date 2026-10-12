import AppKit
import ImageIO

/// A decoded image ready to display.
struct LoadedImage: Sendable {
    let url: URL
    let image: NSImage
    /// Size of the full image in pixels, before any downsampling for display.
    let pixelSize: CGSize
}

/// Fetches preview candidates in order and decodes the first one that works.
actor ImageLoader {
    /// Downloaded images, on disk. Settings shows its size and can clear it. Little is kept in memory:
    /// the decoded images below are what's shown again.
    static let diskCache = URLCache(
        memoryCapacity: 8 << 20, diskCapacity: 512 << 20,
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "HoverEnhance/Images")
    )

    /// Even Load Anyway stops here: no image needs more, and a response that never ends would otherwise
    /// fill memory.
    static let largestEver: Int64 = 1_000_000_000

    enum Outcome: Sendable {
        case loaded(LoadedImage)
        /// Over the size limit, and not downloaded: its size in bytes, when the server said.
        case tooLarge(URL, bytes: Int64?)
        case failed
    }

    private let downloader: LimitedDownloader
    private let decoded = NSCache<NSURL, CacheEntry>()

    init(configuration: URLSessionConfiguration = ImageLoader.configuration()) {
        downloader = LimitedDownloader(configuration: configuration)
        // Enough for an album's neighbors and recent hovers; each can be as large as the screen, and an
        // older one comes back from the disk cache quickly. NSCache also gives them up under memory pressure.
        decoded.countLimit = 12
        decoded.totalCostLimit = 128 << 20
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = diskCache
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["Accept": "image/avif,image/webp,image/apng,image/*;q=0.9,*/*;q=0.5"]
        return configuration
    }

    /// Returns the first candidate that loads. `page` is the page showing the image; some image hosts
    /// refuse requests without a Referer from their own site. A candidate larger than `byteLimit`
    /// isn't downloaded, and ends the search: the caller says how big it is and offers to load it.
    func load(_ candidates: [URL], page: URL?, maxPixelSize: Int, byteLimit: Int64?) async -> Outcome {
        for url in candidates {
            if Task.isCancelled { return .failed }
            if let entry = decoded.object(forKey: url as NSURL) { return .loaded(entry.image) }
            switch await fetch(url, page: page, maxPixelSize: maxPixelSize, byteLimit: byteLimit) {
            case .loaded(let image):
                let cost = Int(image.image.size.width * image.image.size.height) * 4
                decoded.setObject(CacheEntry(image), forKey: url as NSURL, cost: cost)
                return .loaded(image)
            case .tooLarge(_, let bytes):
                return .tooLarge(url, bytes: bytes)
            case .failed:
                continue
            }
        }
        return .failed
    }

    private func fetch(_ url: URL, page: URL?, maxPixelSize: Int, byteLimit: Int64?) async -> Outcome {
        var request = URLRequest(url: url)
        if let referer = page.flatMap({ Self.referer(from: $0, to: url) }) {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        switch await downloader.data(for: request, limit: byteLimit) {
        case .data(let data, let response):
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return .failed }
            return ImageDecoder.decode(data, from: url, maxPixelSize: maxPixelSize).map(Outcome.loaded) ?? .failed
        case .tooLarge(let bytes):
            return .tooLarge(url, bytes: bytes)
        case .failed:
            return .failed
        }
    }

    /// The page's origin, as browsers send cross-site by default (strict-origin-when-cross-origin);
    /// nothing when going from HTTPS to HTTP or from a non-web page.
    static func referer(from page: URL, to target: URL) -> String? {
        guard let scheme = page.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = page.host(), target.scheme?.lowercased() == "https" || scheme == "http" else { return nil }
        return "\(scheme)://\(host)\(page.port.map { ":\($0)" } ?? "")/"
    }

    private final class CacheEntry {
        let image: LoadedImage
        init(_ image: LoadedImage) { self.image = image }
    }
}

enum ImageDecoder {
    /// Decodes `data`, downsampling stills so the long edge is at most `maxPixelSize`. Animated
    /// images are kept whole so `NSImageView` can play them.
    static func decode(_ data: Data, from url: URL, maxPixelSize: Int) -> LoadedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            // Not something ImageIO reads (SVG, for one); NSImage may still manage.
            return NSImage(data: data).map { LoadedImage(url: url, image: $0, pixelSize: $0.size) }
        }
        // EXIF orientations 5–8 turn the image 90°.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let pixelSize = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)

        if CGImageSourceGetCount(source) > 1, let image = NSImage(data: data) {
            image.size = pixelSize
            return LoadedImage(url: url, image: image, pixelSize: pixelSize)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Decode now, on this thread, rather than lazily on the main thread at first draw.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return LoadedImage(url: url, image: image, pixelSize: pixelSize)
    }
}

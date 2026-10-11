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
    /// Downloaded images, on disk. Settings shows its size and can clear it.
    static let diskCache = URLCache(
        memoryCapacity: 32 << 20, diskCapacity: 512 << 20,
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "HoverEnhance/Images")
    )

    private let session: URLSession
    private let decoded = NSCache<NSURL, CacheEntry>()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = Self.diskCache
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["Accept": "image/avif,image/webp,image/apng,image/*;q=0.9,*/*;q=0.5"]
        session = URLSession(configuration: configuration)
        decoded.totalCostLimit = 256 << 20
    }

    /// Returns the first candidate that loads, or nil. `page` is the page showing the image; some
    /// image hosts refuse requests without a Referer from their own site.
    func load(_ candidates: [URL], page: URL?, maxPixelSize: Int) async -> LoadedImage? {
        for url in candidates {
            if Task.isCancelled { return nil }
            if let entry = decoded.object(forKey: url as NSURL) { return entry.image }
            guard let image = await fetch(url, page: page, maxPixelSize: maxPixelSize) else { continue }
            let cost = Int(image.image.size.width * image.image.size.height) * 4
            decoded.setObject(CacheEntry(image), forKey: url as NSURL, cost: cost)
            return image
        }
        return nil
    }

    private func fetch(_ url: URL, page: URL?, maxPixelSize: Int) async -> LoadedImage? {
        var request = URLRequest(url: url)
        if let referer = page.flatMap({ Self.referer(from: $0, to: url) }) {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return ImageDecoder.decode(data, from: url, maxPixelSize: maxPixelSize)
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

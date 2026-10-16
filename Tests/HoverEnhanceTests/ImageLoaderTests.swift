import AppKit
import ImageIO
import os
import Testing
import UniformTypeIdentifiers
@testable import HoverEnhance

struct ImageDecoderTests {
    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func decodedWidth(_ image: LoadedImage) -> Int? {
        image.image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width
    }

    @Test func downsamplesLargeStillsButReportsFullSize() throws {
        let url = URL(string: "https://example.com/big.png")!
        let image = try #require(ImageDecoder.decode(try png(width: 2000, height: 1000), from: url, maxPixelSize: 500))
        #expect(image.pixelSize == CGSize(width: 2000, height: 1000))
        #expect(decodedWidth(image) == 500)
    }

    @Test func leavesSmallImagesAlone() throws {
        let url = URL(string: "https://example.com/small.png")!
        let image = try #require(ImageDecoder.decode(try png(width: 300, height: 200), from: url, maxPixelSize: 500))
        #expect(image.pixelSize == CGSize(width: 300, height: 200))
        #expect(decodedWidth(image) == 300)
    }

    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func file(_ type: UTType, frames: [CGImage]) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, frames.count, nil))
        for frame in frames { CGImageDestinationAddImage(destination, frame, nil) }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func picture(_ data: Data, largestStill: Int = ImageDecoder.Picture.largestStill,
                         largestFrame: Int = ImageDecoder.Picture.largestFrame) throws -> ImageDecoder.Picture {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(ImageDecoder.Picture(source, largestStill: largestStill, largestFrame: largestFrame))
    }

    @Test func refusesPicturesTooLargeToDecode() throws {
        // A real one takes hundreds of megabytes to make; the limit is lowered instead.
        let still = try picture(try png(width: 2000, height: 1000), largestStill: 1_000_000)
        #expect(still.pixelSize == CGSize(width: 2000, height: 1000) && !still.isDecodable)
        #expect(try picture(try png(width: 2000, height: 1000)).isDecodable)

        // An animation with frames too large to play is shown as a still of its first.
        let gif = try file(.gif, frames: [image(width: 400, height: 300), image(width: 400, height: 300)])
        let frames = try picture(gif, largestFrame: 100_000)
        #expect(!frames.isAnimation && frames.isDecodable && frames.index == 0)
    }

    @Test func playsAnimationsButDownsamplesOtherMultiPictureFiles() throws {
        let gif = try file(.gif, frames: [image(width: 40, height: 30), image(width: 40, height: 30)])
        #expect(try picture(gif).isAnimation)

        // A TIFF's pages aren't an animation: the largest is shown, downsampled like any still.
        let tiff = try file(.tiff, frames: [image(width: 40, height: 30), image(width: 2000, height: 1000)])
        let pages = try picture(tiff)
        #expect(!pages.isAnimation && pages.index == 1 && pages.pixelSize == CGSize(width: 2000, height: 1000))
        let decoded = try #require(ImageDecoder.decode(tiff, from: URL(string: "https://example.com/pages.tiff")!, maxPixelSize: 500))
        #expect(decodedWidth(decoded) == 500)
    }

    @Test func rejectsNonImages() {
        let html = Data("<html><body>Sign in</body></html>".utf8)
        #expect(ImageDecoder.decode(html, from: URL(string: "https://example.com/a.jpg")!, maxPixelSize: 500) == nil)
    }
}

struct RefererTests {
    private func referer(_ page: String, _ target: String) -> String? {
        ImageLoader.referer(from: URL(string: page)!, to: URL(string: target)!)
    }

    @Test func sendsOnlyTheOrigin() {
        #expect(referer("https://www.reddit.com/r/pics/comments/abc/?sort=top", "https://i.redd.it/x.jpg") == "https://www.reddit.com/")
        #expect(referer("http://localhost:8080/gallery", "http://localhost:8080/a.png") == "http://localhost:8080/")
    }

    @Test func sendsNothingOnDowngradeOrFromNonWebPages() {
        #expect(referer("https://example.com/", "http://images.example.com/a.png") == nil)
        #expect(referer("file:///Users/me/test.html", "https://example.com/a.png") == nil)
    }
}

/// Serves https://stub.test/<name>.png?size=<bytes>[&declare=0][&claim=<bytes>][&status=<code>][&cookie=<value>]:
/// a small PNG padded to `size` bytes, sent in 64 KB pieces, with a Content-Length unless `declare=0`, or
/// `claim` if given, and setting the cookie `id` to `cookie` if given. It counts the requests for each
/// address, and keeps the Cookie header of the last.
final class StubImageServer: URLProtocol, @unchecked Sendable {
    private static let counts = OSAllocatedUnfairLock<[URL: Int]>(initialState: [:])
    static func requests(for url: URL) -> Int { counts.withLock { $0[url] ?? 0 } }
    private static let cookies = OSAllocatedUnfairLock<[URL: String]>(initialState: [:])
    static func cookieSent(to url: URL) -> String? { cookies.withLock { $0[url] } }

    static let png: Data = {
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageServer.self]
        configuration.urlCache = nil
        return configuration
    }

    static func url(size: Int, declared: Bool = true) -> URL {
        URL(string: "https://stub.test/image-\(size).png?size=\(size)\(declared ? "" : "&declare=0")")!
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "stub.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        Self.counts.withLock { $0[url, default: 0] += 1 }
        Self.cookies.withLock { $0[url] = request.value(forHTTPHeaderField: "Cookie") }
        let size = items.first { $0.name == "size" }?.value.flatMap(Int.init) ?? 0
        let status = items.first { $0.name == "status" }?.value.flatMap(Int.init) ?? 200
        var body = Self.png
        if body.count < size { body.append(Data(count: size - body.count)) }
        var headers = ["Content-Type": "image/png"]
        if let cookie = items.first(where: { $0.name == "cookie" })?.value { headers["Set-Cookie"] = "id=\(cookie); Path=/" }
        if items.first(where: { $0.name == "declare" })?.value != "0" {
            headers["Content-Length"] = items.first { $0.name == "claim" }?.value ?? "\(body.count)"
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var offset = 0
        while offset < body.count {
            let end = min(offset + 65_536, body.count)
            client?.urlProtocol(self, didLoad: body.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct ImageSizeLimitTests {
    private let downloader = LimitedDownloader(configuration: StubImageServer.configuration())

    private func bytes(_ outcome: LimitedDownloader.Outcome) -> Int? {
        if case .data(let data, _) = outcome { data.count } else { nil }
    }

    @Test func imagesUnderTheLimitDownload() async {
        let outcome = await downloader.data(for: URLRequest(url: StubImageServer.url(size: 5_000)), limit: 10_000)
        #expect(bytes(outcome) == 5_000)
        #expect(bytes(await downloader.data(for: URLRequest(url: StubImageServer.url(size: 3_000_000)), limit: nil)) == 3_000_000)
    }

    @Test func aLargerContentLengthStopsTheDownload() async {
        let outcome = await downloader.data(for: URLRequest(url: StubImageServer.url(size: 3_000_000)), limit: 1_000_000)
        guard case .tooLarge(let size) = outcome else { Issue.record("expected tooLarge, got \(outcome)"); return }
        #expect(size == 3_000_000)
    }

    @Test func anImpossibleContentLengthIsRefusedWithoutReservingIt() async {
        let claim = "100000000000000000"
        let url = URL(string: "https://stub.test/huge.png?size=1000&claim=\(claim)")!
        let outcome = await downloader.data(for: URLRequest(url: url), limit: 1_000_000)
        guard case .tooLarge(let size) = outcome else { Issue.record("expected tooLarge, got \(outcome)"); return }
        #expect(size == Int64(claim))
        // Without a limit, only a sensible amount is set aside; this would crash if the claim were believed.
        _ = await downloader.data(for: URLRequest(url: url), limit: nil)
    }

    @Test func withoutAContentLengthItStopsAtTheLimit() async {
        let outcome = await downloader.data(for: URLRequest(url: StubImageServer.url(size: 3_000_000, declared: false)), limit: 1_000_000)
        guard case .tooLarge(let size) = outcome else { Issue.record("expected tooLarge, got \(outcome)"); return }
        #expect(size == nil)
    }

    @Test func aMissingCandidateIsntAskedForAgainRightAway() async {
        let loader = ImageLoader(configuration: StubImageServer.configuration())
        let missing = URL(string: "https://stub.test/maxres-\(UUID().uuidString).png?size=100&status=404")!
        let present = StubImageServer.url(size: 1_000)
        for _ in 0..<2 {
            guard case .loaded = await loader.load([missing, present], page: nil, maxPixelSize: 500, byteLimit: nil) else {
                Issue.record("expected the second candidate to load"); return
            }
        }
        #expect(StubImageServer.requests(for: missing) == 1)
    }

    @Test func theLoaderOffersTheLargeImageAndLoadsItWhenAsked() async throws {
        let loader = ImageLoader(configuration: StubImageServer.configuration())
        let big = StubImageServer.url(size: 2_000_000)
        let small = StubImageServer.url(size: 1_000)

        // Too large ends the search rather than falling back to a smaller candidate.
        let limited = await loader.load([big, small], page: nil, maxPixelSize: 500, byteLimit: 1_000_000)
        guard case .tooLarge(let url, let size) = limited else { Issue.record("expected tooLarge, got \(limited)"); return }
        #expect(url == big && size == 2_000_000)

        let anyway = await loader.load([big, small], page: nil, maxPixelSize: 500, byteLimit: nil)
        guard case .loaded(let image) = anyway else { Issue.record("expected loaded, got \(anyway)"); return }
        #expect(image.url == big && image.pixelSize == CGSize(width: 40, height: 30))
    }
}

struct ImageCookieTests {
    /// A downloader as the image loader makes one, with a fresh cookie storage: the session keeps none,
    /// and only addresses with "known" in their path share cookies.
    private func downloader() -> (LimitedDownloader, HTTPCookieStorage) {
        let configuration = StubImageServer.configuration()
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let storage = URLSessionConfiguration.ephemeral.httpCookieStorage!
        return (LimitedDownloader(configuration: configuration, cookieStorage: storage) { $0.path().contains("known") }, storage)
    }

    @Test func otherHostsCantSetACookieAndReadItBack() async {
        let (downloader, storage) = downloader()
        let tracker = URL(string: "https://stub.test/pixel.png?size=100&cookie=\(UUID().uuidString)")!
        _ = await downloader.data(for: URLRequest(url: tracker), limit: nil)
        #expect(storage.cookies?.isEmpty == true)
        _ = await downloader.data(for: URLRequest(url: tracker), limit: nil)
        #expect(StubImageServer.cookieSent(to: tracker) == nil)
        // Nor does a cookie the request arrives with go along.
        var request = URLRequest(url: tracker)
        request.setValue("id=smuggled", forHTTPHeaderField: "Cookie")
        _ = await downloader.data(for: request, limit: nil)
        #expect(StubImageServer.cookieSent(to: tracker) == nil)
    }

    @Test func knownSitesKeepTheirCookies() async {
        let (downloader, storage) = downloader()
        let value = UUID().uuidString
        let site = URL(string: "https://stub.test/known/a.png?size=100&cookie=\(value)")!
        _ = await downloader.data(for: URLRequest(url: site), limit: nil)
        #expect(storage.cookies?.map(\.value) == [value])
        let next = URL(string: "https://stub.test/known/b.png?size=100")!
        _ = await downloader.data(for: URLRequest(url: next), limit: nil)
        #expect(StubImageServer.cookieSent(to: next) == "id=\(value)")
    }
}

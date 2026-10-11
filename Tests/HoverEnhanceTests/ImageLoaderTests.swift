import AppKit
import ImageIO
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

/// Serves https://stub.test/<name>.png?size=<bytes>[&declare=0]: a small PNG padded to `size` bytes,
/// sent in 64 KB pieces, with a Content-Length unless `declare=0`.
final class StubImageServer: URLProtocol, @unchecked Sendable {
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
        let size = items.first { $0.name == "size" }?.value.flatMap(Int.init) ?? 0
        var body = Self.png
        if body.count < size { body.append(Data(count: size - body.count)) }
        var headers = ["Content-Type": "image/png"]
        if items.first(where: { $0.name == "declare" })?.value != "0" { headers["Content-Length"] = "\(body.count)" }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
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

    @Test func withoutAContentLengthItStopsAtTheLimit() async {
        let outcome = await downloader.data(for: URLRequest(url: StubImageServer.url(size: 3_000_000, declared: false)), limit: 1_000_000)
        guard case .tooLarge(let size) = outcome else { Issue.record("expected tooLarge, got \(outcome)"); return }
        #expect(size == nil)
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

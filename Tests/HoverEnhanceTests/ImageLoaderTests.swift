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

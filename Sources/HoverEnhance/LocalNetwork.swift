import Foundation

/// Addresses on this Mac or the local network: loopback, private and link-local ranges, carrier-grade
/// NAT, `localhost`, Bonjour's `.local`, the home and private-use names (`.home.arpa`, `.internal`,
/// `.lan`), and single-label names, which only a local resolver answers. A web page mustn't lead
/// HoverEnhance there: a hover would reach a router or printer the page itself can't, and ask macOS for
/// local network access. Only names and address literals are checked, so a public name that resolves to
/// a local address isn't caught, and a video's redirects aren't either: AVPlayer follows them itself.
enum LocalNetwork {
    static func contains(_ url: URL?) -> Bool {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host(percentEncoded: false) else { return false }
        return contains(host: host)
    }

    static func contains(host rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        if host.isEmpty { return false }

        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 { return contains(v6) }
        // inet_aton reads every form the resolver does: "10.1", "0x0a000001", "012.0.0.1".
        var v4 = in_addr()
        if inet_aton(host, &v4) == 1 { return contains(UInt32(bigEndian: v4.s_addr)) }

        if host == "localhost" || [".localhost", ".local", ".home.arpa", ".internal", ".lan"].contains(where: host.hasSuffix) { return true }
        return !host.contains(".")
    }

    /// An IPv4 address, in host byte order.
    private static func contains(_ address: UInt32) -> Bool {
        let ranges: [(base: UInt32, bits: UInt32)] = [
            (0x0000_0000, 8),   // "this network", including 0.0.0.0
            (0x0A00_0000, 8),   // 10/8
            (0x6440_0000, 10),  // 100.64/10, carrier-grade NAT
            (0x7F00_0000, 8),   // 127/8, loopback
            (0xA9FE_0000, 16),  // 169.254/16, link-local
            (0xAC10_0000, 12),  // 172.16/12
            (0xC0A8_0000, 16),  // 192.168/16
            (0xE000_0000, 4),   // multicast
            (0xF000_0000, 4),   // reserved, and broadcast
        ]
        return ranges.contains { address >> (32 - $0.bits) == $0.base >> (32 - $0.bits) }
    }

    private static func contains(_ address: in6_addr) -> Bool {
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        if bytes[0 ..< 15].allSatisfy({ $0 == 0 }) { return true } // :: and ::1
        if bytes[0] & 0xFE == 0xFC { return true }                // fc00::/7, unique local
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true } // fe80::/10, link-local
        if bytes[0] == 0xFF { return true }                       // multicast
        // ::ffff:a.b.c.d, an IPv4 address written as IPv6.
        if bytes[0 ..< 10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return contains(bytes[12 ..< 16].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        }
        return false
    }
}

/// Refuses redirects from the web onto the local network. A redirect that's refused ends the request
/// with the redirect's own response, which callers already treat as a failure.
final class LocalRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = LocalRedirectGuard()

    static func allows(from original: URL?, to target: URL?) -> Bool {
        LocalNetwork.contains(original) || !LocalNetwork.contains(target)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(Self.allows(from: task.originalRequest?.url, to: request.url) ? request : nil)
    }
}

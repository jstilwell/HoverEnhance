import Foundation

/// How the internet sees this Mac: its public address and who provides it, from addr.fyi.
struct PublicAddress: Sendable, Equatable {
    var ip: String
    /// The network the address belongs to, as its owner registered it: "WINDSTREAM COMMUNICATIONS LLC".
    var organization: String?
    var asn: Int?
    var city: String?
    var region: String?
    var country: String?
    /// The Cloudflare data center that answered, as "ATL": where traffic meets the wider internet.
    var edge: String?
    /// Milliseconds for one round trip to that data center, from how long the connection took to open.
    var latency: Double?
    var fetched: Date

    /// "Charlotte, North Carolina", or as much of it as is known.
    var place: String? {
        let parts = [city, region ?? country].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "Windstream Communications", without the shouting or the company suffix.
    var provider: String? {
        guard let organization, !organization.isEmpty else { return nil }
        let isShouting = organization == organization.uppercased()
        var words = organization.split(separator: " ").map(String.init)
        if let last = words.last, words.count > 1, ["LLC", "INC", "INC.", "LTD", "LTD.", "CORP", "CORP.", "CO.", "LP", "GMBH", "AG", "SA", "BV"]
            .contains(last.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ","))) {
            words.removeLast()
        }
        let joined = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        return isShouting ? joined.capitalized : joined
    }

    /// Reads addr.fyi's `/json` answer.
    static func read(_ data: Data, latency: Double?, fetched: Date) -> PublicAddress? {
        struct Answer: Decodable {
            var ip: String
            var org: String?
            var asn: Int?
            var city: String?
            var region: String?
            var country: String?
            var colo: String?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data), !answer.ip.isEmpty else { return nil }
        return PublicAddress(ip: answer.ip, organization: answer.org, asn: answer.asn, city: answer.city, region: answer.region,
                             country: answer.country, edge: answer.colo, latency: latency, fetched: fetched)
    }
}

/// Looks up the public address, keeping it until the network changes or five minutes pass.
@MainActor
final class PublicAddressService {
    static let shared = PublicAddressService()
    static let endpoint = URL(string: "https://addr.fyi/json")!
    static let page = URL(string: "https://addr.fyi")!
    private static let lifetime: TimeInterval = 5 * 60

    /// The answer, and the network it was for: a new router or Wi-Fi network means a new address.
    private var kept: (address: PublicAddress, network: String)?
    private var inFlight: (network: String, task: Task<PublicAddress?, Never>)?

    private let session: URLSession = {
        // Ephemeral, so each lookup opens its own connection, whose setup time is the round trip.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    func kept(for network: String) -> PublicAddress? {
        guard let kept, kept.network == network, Date().timeIntervalSince(kept.address.fetched) < Self.lifetime else { return nil }
        return kept.address
    }

    func lookUp(for network: String) async -> PublicAddress? {
        if let address = kept(for: network) { return address }
        if let inFlight, inFlight.network == network { return await inFlight.task.value }
        let session = session
        let task = Task { await Self.fetch(with: session) }
        inFlight = (network, task)
        let address = await task.value
        if inFlight?.network == network { inFlight = nil }
        if let address { kept = (address, network) }
        return address
    }

    private nonisolated static func fetch(with session: URLSession) async -> PublicAddress? {
        let timing = ConnectionTiming()
        guard let (data, response) = try? await session.data(for: URLRequest(url: endpoint), delegate: timing),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return PublicAddress.read(data, latency: timing.roundTrip, fetched: Date())
    }
}

/// Times the TCP handshake of a request's connection, which takes one round trip.
private final class ConnectionTiming: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var measured: Double?

    var roundTrip: Double? { lock.withLock { measured } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last(where: { $0.connectStartDate != nil }),
              let start = transaction.connectStartDate,
              let end = transaction.secureConnectionStartDate ?? transaction.connectEndDate else { return }
        let milliseconds = end.timeIntervalSince(start) * 1000
        lock.withLock { measured = milliseconds > 0 ? milliseconds : nil }
    }
}

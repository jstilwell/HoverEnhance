import Foundation

/// The weather services a forecast can come from.
enum WeatherProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case openMeteo, openWeatherMap, weatherAPI, tomorrow, pirateWeather

    var id: Self { self }

    var name: String {
        switch self {
        case .openMeteo: "Open-Meteo"
        case .openWeatherMap: "OpenWeatherMap"
        case .weatherAPI: "WeatherAPI.com"
        case .tomorrow: "Tomorrow.io"
        case .pirateWeather: "Pirate Weather"
        }
    }

    /// What it's good at, for Settings.
    var detail: String {
        switch self {
        case .openMeteo: "Free, no key or account. Hourly and 10-day forecasts, air quality, rain by the quarter hour in Europe and North America."
        case .openWeatherMap: "Free key. 5-day forecast in 3-hour steps, air quality."
        case .weatherAPI: "Free key. 3-day forecast, air quality, and weather alerts."
        case .tomorrow: "Free key. Rain minute by minute, 5-day forecast. The free plan allows 25 lookups an hour."
        case .pirateWeather: "Free key. Rain minute by minute, 8-day forecast, and weather alerts."
        }
    }

    var needsKey: Bool { self != .openMeteo }

    /// Where to get a key.
    var keyPage: URL? {
        switch self {
        case .openMeteo: nil
        case .openWeatherMap: URL(string: "https://home.openweathermap.org/api_keys")
        case .weatherAPI: URL(string: "https://www.weatherapi.com/signup.aspx")
        case .tomorrow: URL(string: "https://app.tomorrow.io/development/keys")
        case .pirateWeather: URL(string: "https://pirate-weather.apiable.io/")
        }
    }

    /// The credit each asks for wherever its data is shown.
    var attribution: (text: String, url: URL) {
        switch self {
        case .openMeteo: ("Weather data by Open-Meteo.com", URL(string: "https://open-meteo.com/")!)
        case .openWeatherMap: ("Weather data from OpenWeather", URL(string: "https://openweathermap.org/")!)
        case .weatherAPI: ("Powered by WeatherAPI.com", URL(string: "https://www.weatherapi.com/")!)
        case .tomorrow: ("Powered by Tomorrow.io", URL(string: "https://www.tomorrow.io/")!)
        case .pirateWeather: ("Powered by Pirate Weather", URL(string: "https://pirateweather.net/")!)
        }
    }

    /// The Keychain account its key is kept under.
    var keychainAccount: String { "weather.\(rawValue)" }

    var source: any WeatherSource {
        switch self {
        case .openMeteo: OpenMeteo()
        case .openWeatherMap: OpenWeatherMap()
        case .weatherAPI: WeatherAPIcom()
        case .tomorrow: TomorrowIO()
        case .pirateWeather: PirateWeather()
        }
    }
}

/// Why there's no forecast, in terms the popup can explain.
enum WeatherError: Error, Equatable, Sendable {
    /// No place is set, or the current one couldn't be found.
    case noLocation
    /// Location Services is off for HoverEnhance.
    case locationDenied
    /// The provider needs a key and none is saved.
    case needsKey
    /// The provider turned the key down.
    case badKey
    case rateLimited
    case offline
    /// The provider answered with something else: its status code, if any.
    case unavailable(Int?)
    /// The answer couldn't be read.
    case unreadable
}

/// A provider's way of getting a forecast for a coordinate.
protocol WeatherSource: Sendable {
    /// `timeZone` is the place's, from where it was found, for providers whose answers don't say.
    func report(at coordinate: Coordinate, key: String?, timeZone: TimeZone, using http: any WeatherHTTP) async throws(WeatherError) -> WeatherReport
}

/// Fetches for weather sources, turning HTTP failures into `WeatherError`s. Tests stand in for it.
protocol WeatherHTTP: Sendable {
    func data(for request: URLRequest) async throws(WeatherError) -> Data
}

struct URLSessionWeatherHTTP: WeatherHTTP {
    let session: URLSession

    static let shared = URLSessionWeatherHTTP(session: {
        let configuration = URLSessionConfiguration.ephemeral
        // A spinner is up while it loads; a forecast that takes longer isn't coming.
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = ["Accept": "application/json, application/geo+json"]
        return URLSession(configuration: configuration)
    }())

    func data(for request: URLRequest) async throws(WeatherError) -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut,
                                             .dnsLookupFailed, .cannotConnectToHost].contains(error.code) {
            throw .offline
        } catch {
            throw .unavailable(nil)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw .unavailable(nil) }
        switch status {
        case 200..<300: return data
        case 401, 403: throw .badKey
        case 429: throw .rateLimited
        default: throw .unavailable(status)
        }
    }
}

/// Helpers for reading providers' JSON loosely: numbers can come as integers or decimals, and any field
/// can be missing.
enum JSON {
    static func object(_ data: Data) throws(WeatherError) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw .unreadable }
        return object
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        // Not `is Bool`, which any NSNumber holding 0 or 1 passes: only JSON's true and false are CFBooleans.
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    static func int(_ value: Any?) -> Int? { double(value).map { Int($0.rounded()) } }

    static func doubles(_ value: Any?) -> [Double?] { (value as? [Any])?.map(double) ?? [] }

    /// An ISO 8601 time, with or without fractional seconds.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return iso.date(from: text) ?? isoFractional.date(from: text)
    }

    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension URLComponents {
    /// `base` with `items` as its query, for building providers' requests.
    static func request(_ base: String, _ items: [String: String]) -> URLRequest? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url.map { URLRequest(url: $0) }
    }
}

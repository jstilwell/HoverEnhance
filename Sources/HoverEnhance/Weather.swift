import Foundation

/// A place on Earth, in degrees.
struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    /// "40.71,-74.01": enough for any forecast (about a kilometer), and no closer, for privacy.
    var query: String { String(format: "%.2f,%.2f", latitude, longitude) }

    /// Rounded to about a kilometer, as `query` sends it, for keying caches.
    var rounded: Coordinate {
        Coordinate(latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100)
    }
}

/// A forecast for one place, whichever provider it came from, in metric units: degrees Celsius, meters
/// per second, hectopascals, millimeters, and kilometers. Anything a provider doesn't give is nil or empty.
struct WeatherReport: Sendable, Equatable {
    var provider: WeatherProviderID
    /// When it was fetched.
    var fetched: Date
    /// The place's time zone, for its hours and days.
    var timeZone: TimeZone
    var current: Current
    /// The next hour, minute by minute or every 15 minutes, where the provider has it.
    var minutely: [Minute] = []
    var hourly: [Hour] = []
    var daily: [Day] = []
    var air: AirQuality?
    var alerts: [WeatherAlert] = []

    struct Current: Sendable, Equatable {
        var time: Date
        var condition: WeatherCondition
        var isDay = true
        var temperature: Double
        var feelsLike: Double?
        /// Percent.
        var humidity: Double?
        var dewPoint: Double?
        /// At sea level.
        var pressure: Double?
        var windSpeed: Double?
        var windGust: Double?
        /// Where the wind comes from, in degrees clockwise from north.
        var windDirection: Double?
        var visibility: Double?
        var uvIndex: Double?
        /// Percent.
        var cloudCover: Double?
        /// Millimeters an hour, now.
        var precipitation: Double?
    }

    struct Minute: Sendable, Equatable {
        var time: Date
        /// Millimeters an hour.
        var intensity: Double
        /// Percent, where given.
        var chance: Double?
    }

    struct Hour: Sendable, Equatable {
        var time: Date
        var condition: WeatherCondition
        var isDay = true
        var temperature: Double
        var feelsLike: Double?
        /// Percent.
        var precipitationChance: Double?
        /// Millimeters in the hour.
        var precipitation: Double?
        var pressure: Double?
        var uvIndex: Double?
        var windSpeed: Double?
    }

    struct Day: Sendable, Equatable {
        /// The day's start, in the place's time zone.
        var date: Date
        var condition: WeatherCondition
        var high: Double
        var low: Double
        /// Percent.
        var precipitationChance: Double?
        /// Millimeters in the day.
        var precipitation: Double?
        var sunrise: Date?
        var sunset: Date?
        var uvIndexMax: Double?
        var windSpeedMax: Double?
    }

    struct AirQuality: Sendable, Equatable {
        /// The US EPA's index for these concentrations, from its breakpoints for particles (PM2.5 as revised
        /// in 2024): for providers that give the amounts but not the index.
        static func usIndex(pm25: Double?, pm10: Double?) -> Int? {
            func index(_ value: Double?, _ breakpoints: [(Double, Double, Int, Int)]) -> Int? {
                guard let value, value >= 0 else { return nil }
                for (low, high, indexLow, indexHigh) in breakpoints where value <= high {
                    return Int((Double(indexHigh - indexLow) / (high - low) * (value - low) + Double(indexLow)).rounded())
                }
                return 500
            }
            let fine = index(pm25.map { ($0 * 10).rounded(.down) / 10 }, [(0, 9, 0, 50), (9.1, 35.4, 51, 100), (35.5, 55.4, 101, 150),
                                                                         (55.5, 125.4, 151, 200), (125.5, 225.4, 201, 300), (225.5, 325.4, 301, 500)])
            let coarse = index(pm10.map { $0.rounded(.down) }, [(0, 54, 0, 50), (55, 154, 51, 100), (155, 254, 101, 150), (255, 354, 151, 200),
                                                                (355, 424, 201, 300), (425, 604, 301, 500)])
            return [fine, coarse].compactMap { $0 }.max()
        }

        /// The US EPA's index, 0–500.
        var usIndex: Int?
        /// The European Environment Agency's index, 0–100+.
        var europeanIndex: Int?
        /// Micrograms per cubic meter.
        var pm25: Double?
        var pm10: Double?
        var ozone: Double?
        var nitrogenDioxide: Double?
    }

    /// The hours from now on, at most `count`.
    func upcomingHours(_ count: Int, from now: Date = Date()) -> [Hour] {
        Array(hourly.drop { $0.time.addingTimeInterval(3600) <= now }.prefix(count))
    }

    /// The forecast for the next day, from the step now on: 25 hours, or nine 3-hour steps where that's
    /// what the provider gives.
    func nextDay(from now: Date = Date()) -> [Hour] {
        let upcoming = hourly.drop { $0.time.addingTimeInterval(stepLength) <= now }
        guard let start = upcoming.first?.time else { return [] }
        return Array(upcoming.prefix { $0.time <= start.addingTimeInterval(24 * 3600) })
    }

    /// Seconds between forecast steps: an hour, or three.
    var stepLength: TimeInterval {
        guard hourly.count >= 2 else { return 3600 }
        return max(3600, hourly[1].time.timeIntervalSince(hourly[0].time))
    }

    /// Whether air pressure is rising or falling over the next three hours, from the hourly forecast.
    func pressureTrend(from now: Date = Date()) -> PressureTrend? {
        let hours = upcomingHours(4, from: now)
        guard let first = hours.first?.pressure ?? current.pressure, let later = hours.last?.pressure, hours.count >= 4 else { return nil }
        let change = later - first
        return abs(change) < 1 ? .steady : change > 0 ? .rising : .falling
    }

    enum PressureTrend: Sendable { case rising, steady, falling }

    /// What the next hour holds for rain or snow, from minute-by-minute data where there is some, or the
    /// next hour's chance otherwise.
    func nextHourPrecipitation(from now: Date = Date()) -> NextHour? {
        let minutes = minutely.filter { $0.time >= now.addingTimeInterval(-60) && $0.time < now.addingTimeInterval(3600) }
        if !minutes.isEmpty {
            // A tenth of a millimeter an hour is the least anyone notices.
            if let start = minutes.first(where: { $0.intensity >= 0.1 }) {
                if start.time <= now.addingTimeInterval(60) {
                    let end = minutes.drop { $0.intensity >= 0.1 }.first { $0.intensity < 0.1 }
                    return .now(until: end?.time)
                }
                return .starting(start.time)
            }
            return .dry
        }
        guard let chance = upcomingHours(1, from: now).first?.precipitationChance else { return nil }
        return .chance(chance)
    }

    enum NextHour: Sendable, Equatable {
        /// Falling now, stopping then if it does within the hour.
        case now(until: Date?)
        case starting(Date)
        /// Nothing falling all hour.
        case dry
        /// Only the hour's chance is known, in percent.
        case chance(Double)
    }
}

/// What the sky's doing, in the few kinds every provider can be mapped onto.
enum WeatherCondition: String, Sendable, CaseIterable {
    case clear, mostlyClear, partlyCloudy, cloudy, fog, haze, drizzle, rain, heavyRain, freezingRain, sleet,
         snow, heavySnow, thunderstorm, hail, windy

    var name: String {
        switch self {
        case .clear: "Clear"
        case .mostlyClear: "Mostly clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .haze: "Haze"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .heavyRain: "Heavy rain"
        case .freezingRain: "Freezing rain"
        case .sleet: "Sleet"
        case .snow: "Snow"
        case .heavySnow: "Heavy snow"
        case .thunderstorm: "Thunderstorms"
        case .hail: "Hail"
        case .windy: "Windy"
        }
    }

    /// An SF Symbol, meant for multicolor rendering.
    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mostlyClear: isDay ? "sun.max.fill" : "moon.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .haze: isDay ? "sun.haze.fill" : "moon.haze.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain, .sleet: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .heavySnow: "snowflake"
        case .thunderstorm: isDay ? "cloud.sun.bolt.fill" : "cloud.moon.bolt.fill"
        case .hail: "cloud.hail.fill"
        case .windy: "wind"
        }
    }

    /// How much it matters, for a day's summary: storms over snow over rain over gray skies over clear.
    private var severity: Int {
        [.clear, .mostlyClear, .partlyCloudy, .cloudy, .windy, .haze, .fog, .drizzle, .rain, .sleet, .freezingRain, .snow,
         .heavyRain, .heavySnow, .hail, .thunderstorm].firstIndex(of: self) ?? 0
    }

    /// The most notable of several, as a day's worth of steps is summed up.
    static func worst(_ conditions: [WeatherCondition]) -> WeatherCondition {
        conditions.max { $0.severity < $1.severity } ?? .cloudy
    }

    /// What's falling, in a word, for "Rain starting around…": snow or sleet where the sky says so.
    var precipitationWord: String {
        switch self {
        case .snow, .heavySnow: "Snow"
        case .sleet: "Sleet"
        case .freezingRain: "Freezing rain"
        case .hail: "Hail"
        default: "Rain"
        }
    }

    /// Whether anything is falling.
    var isPrecipitation: Bool {
        switch self {
        case .drizzle, .rain, .heavyRain, .freezingRain, .sleet, .snow, .heavySnow, .thunderstorm, .hail: true
        case .clear, .mostlyClear, .partlyCloudy, .cloudy, .fog, .haze, .windy: false
        }
    }
}

/// A watch or warning for the place.
struct WeatherAlert: Sendable, Equatable {
    enum Severity: Int, Sendable, Comparable {
        case unknown, minor, moderate, severe, extreme

        init(_ text: String?) {
            switch text?.lowercased() {
            case "extreme": self = .extreme
            case "severe": self = .severe
            case "moderate": self = .moderate
            case "minor": self = .minor
            default: self = .unknown
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var title: String
    var severity: Severity = .unknown
    var starts: Date?
    var ends: Date?
    var detail: String?
    /// Who issued it.
    var source: String?
    /// More about it, on the web.
    var url: URL?
}

/// The Moon's phase, worked out from the date: every provider's answer would be the same.
struct MoonPhase: Sendable, Equatable {
    /// 0 at new moon, 0.5 at full, back to 1.
    let fraction: Double

    /// A new moon to count from (6 January 2000, 18:14 UTC) and the average lunar month, in days.
    private static let knownNewMoon = Date(timeIntervalSince1970: 947_182_440)
    private static let synodicMonth = 29.530_588_853

    init(at date: Date) {
        let days = date.timeIntervalSince(Self.knownNewMoon) / 86400
        let cycles = days / Self.synodicMonth
        fraction = cycles - cycles.rounded(.down)
    }

    /// The share of the face that's lit, 0 to 1.
    var illumination: Double { (1 - cos(2 * .pi * fraction)) / 2 }

    private var index: Int { Int((fraction * 8).rounded()) % 8 }

    var name: String {
        ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon", "Waning gibbous", "Last quarter",
         "Waning crescent"][index]
    }

    var symbol: String {
        ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter", "moonphase.waxing.gibbous",
         "moonphase.full.moon", "moonphase.waning.gibbous", "moonphase.last.quarter", "moonphase.waning.crescent"][index]
    }
}

/// The menu bar item hovering shows the forecast for: Apple's Weather.
enum WeatherTrigger {
    static let bundleID = "com.apple.weather.menu"

    static func matches(_ info: HoverInfo) -> Bool {
        info.bundleID == bundleID && info.subrole == "AXMenuExtra"
    }
}

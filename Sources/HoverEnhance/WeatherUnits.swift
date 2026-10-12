import Foundation

/// How the popup writes temperatures, speeds, and the rest. Reports are metric; these convert them.
struct WeatherUnits: Codable, Equatable, Sendable {
    enum Temperature: String, Codable, CaseIterable, Identifiable, Sendable {
        case fahrenheit, celsius
        var id: Self { self }
        var label: String { self == .fahrenheit ? "°F" : "°C" }
    }

    enum Speed: String, Codable, CaseIterable, Identifiable, Sendable {
        case mph, kmh, ms, knots
        var id: Self { self }
        var label: String {
            switch self {
            case .mph: "mph"
            case .kmh: "km/h"
            case .ms: "m/s"
            case .knots: "kn"
            }
        }
    }

    enum Pressure: String, Codable, CaseIterable, Identifiable, Sendable {
        case inHg, hPa, mmHg
        var id: Self { self }
        var label: String { rawValue }
    }

    enum Precipitation: String, Codable, CaseIterable, Identifiable, Sendable {
        case inches, millimeters
        var id: Self { self }
        var label: String { self == .inches ? "in" : "mm" }
    }

    enum Distance: String, Codable, CaseIterable, Identifiable, Sendable {
        case miles, kilometers
        var id: Self { self }
        var label: String { self == .miles ? "mi" : "km" }
    }

    var temperature: Temperature
    var speed: Speed
    var pressure: Pressure
    var precipitation: Precipitation
    var distance: Distance

    /// What people where the Mac is set to use: US customary, the UK's mix, or metric.
    static func forLocale(_ locale: Locale = .current) -> WeatherUnits {
        switch locale.measurementSystem {
        case .us: WeatherUnits(temperature: .fahrenheit, speed: .mph, pressure: .inHg, precipitation: .inches, distance: .miles)
        case .uk: WeatherUnits(temperature: .celsius, speed: .mph, pressure: .hPa, precipitation: .millimeters, distance: .miles)
        default: WeatherUnits(temperature: .celsius, speed: .kmh, pressure: .hPa, precipitation: .millimeters, distance: .kilometers)
        }
    }

    // MARK: - Writing values

    /// "61°", from degrees Celsius.
    func degrees(_ celsius: Double) -> String {
        let value = temperature == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        // Rounded first, so -0.4 doesn't come out as "-0°".
        let rounded = Int(value.rounded())
        return "\(rounded)°"
    }

    /// "8 mph", from meters per second.
    func wind(_ metersPerSecond: Double) -> String {
        let value = switch speed {
        case .mph: metersPerSecond * 2.236_936
        case .kmh: metersPerSecond * 3.6
        case .ms: metersPerSecond
        case .knots: metersPerSecond * 1.943_844
        }
        return "\(Int(value.rounded())) \(speed.label)"
    }

    /// "30.02 inHg", from hectopascals.
    func pressure(_ hectopascals: Double) -> String {
        switch pressure {
        case .inHg: String(format: "%.2f inHg", hectopascals * 0.029_53)
        case .hPa: "\(Int(hectopascals.rounded())) hPa"
        case .mmHg: "\(Int((hectopascals * 0.750_062).rounded())) mmHg"
        }
    }

    /// "0.12 in" or "3 mm", from millimeters; small amounts keep a decimal.
    func precipitation(_ millimeters: Double) -> String {
        switch precipitation {
        case .inches: String(format: "%.2f in", millimeters / 25.4)
        case .millimeters: millimeters < 10 ? String(format: "%.1f mm", millimeters) : "\(Int(millimeters.rounded())) mm"
        }
    }

    /// "10 mi", from kilometers.
    func distance(_ kilometers: Double) -> String {
        let value = distance == .miles ? kilometers * 0.621_371 : kilometers
        // Decided after rounding, so 9.98 is "10 mi", not "10.0 mi".
        return (value * 10).rounded() < 100 ? String(format: "%.1f %@", value, distance.label) : "\(Int(value.rounded())) \(distance.label)"
    }
}

/// Words for numbers the popup shows.
enum WeatherWords {
    /// "NW", one of sixteen points, from degrees clockwise from north.
    static func compass(_ degrees: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 22.5 + 0.5) % 16
        return points[index]
    }

    /// The World Health Organization's bands for the UV index.
    static func uvLevel(_ index: Double) -> String {
        switch index {
        case ..<3: "Low"
        case ..<6: "Moderate"
        case ..<8: "High"
        case ..<11: "Very high"
        default: "Extreme"
        }
    }

    /// The US EPA's air quality categories.
    static func airQuality(us index: Int) -> (name: String, level: Int) {
        switch index {
        case ...50: ("Good", 0)
        case ...100: ("Moderate", 1)
        case ...150: ("Unhealthy for sensitive groups", 2)
        case ...200: ("Unhealthy", 3)
        case ...300: ("Very unhealthy", 4)
        default: ("Hazardous", 5)
        }
    }

    /// The European Environment Agency's air quality categories.
    static func airQuality(european index: Int) -> (name: String, level: Int) {
        switch index {
        case ...20: ("Good", 0)
        case ...40: ("Fair", 1)
        case ...60: ("Moderate", 2)
        case ...80: ("Poor", 3)
        case ...100: ("Very poor", 4)
        default: ("Extremely poor", 5)
        }
    }

    /// "11h 29m".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

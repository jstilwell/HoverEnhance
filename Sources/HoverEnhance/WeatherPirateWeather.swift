import Foundation

/// Pirate Weather, a Dark Sky–style API, with the user's key: everything in one request, in SI units,
/// with version 2's extra fields and air quality details. Humidity, cloud cover, and chances come as
/// fractions; accumulations in centimeters.
struct PirateWeather: WeatherSource {
    static func request(at coordinate: Coordinate, key: String) -> URLRequest? {
        // Everything but letters and digits encoded, so nothing pasted with the key can change the path.
        guard let path = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URLComponents.request("https://api.pirateweather.net/forecast/\(path)/\(coordinate.query)", [
            "units": "si", "version": "2", "include": "airqualitydetails",
        ])
    }

    func report(at coordinate: Coordinate, key: String?, timeZone: TimeZone, using http: any WeatherHTTP) async throws(WeatherError) -> WeatherReport {
        guard let key, let request = Self.request(at: coordinate, key: key) else { throw .needsKey }
        return try Self.report(from: await http.data(for: request), timeZone: timeZone, fetched: Date())
    }

    static func report(from data: Data, timeZone place: TimeZone, fetched: Date) throws(WeatherError) -> WeatherReport {
        let json = try JSON.object(data)
        guard let now = json["currently"] as? [String: Any], let temperature = JSON.double(now["temperature"]),
              let time = JSON.double(now["time"]) else { throw .unreadable }
        let timeZone = (json["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? place
        func percent(_ value: Any?) -> Double? { JSON.double(value).map { $0 * 100 } }
        func points(_ block: String) -> [[String: Any]] { ((json[block] as? [String: Any])?["data"] as? [[String: Any]]) ?? [] }

        var report = WeatherReport(provider: .pirateWeather, fetched: fetched, timeZone: timeZone, current: .init(
            time: Date(timeIntervalSince1970: time),
            condition: condition(now),
            isDay: isDay(now["icon"] as? String, at: time, days: points("daily")),
            temperature: temperature,
            feelsLike: JSON.double(now["apparentTemperature"]),
            humidity: percent(now["humidity"]),
            dewPoint: JSON.double(now["dewPoint"]),
            pressure: JSON.double(now["pressure"]),
            windSpeed: JSON.double(now["windSpeed"]),
            windGust: JSON.double(now["windGust"]),
            windDirection: JSON.double(now["windBearing"]),
            visibility: JSON.double(now["visibility"]),
            uvIndex: JSON.double(now["uvIndex"]),
            cloudCover: percent(now["cloudCover"]),
            precipitation: JSON.double(now["precipIntensity"])
        ))
        report.minutely = points("minutely").compactMap { minute in
            guard let time = JSON.double(minute["time"]) else { return nil }
            return .init(time: Date(timeIntervalSince1970: time), intensity: JSON.double(minute["precipIntensity"]) ?? 0, chance: percent(minute["precipProbability"]))
        }
        report.hourly = points("hourly").compactMap { hour -> WeatherReport.Hour? in
            guard let time = JSON.double(hour["time"]), let temperature = JSON.double(hour["temperature"]) else { return nil }
            return WeatherReport.Hour(
                time: Date(timeIntervalSince1970: time), condition: condition(hour), isDay: isDay(hour["icon"] as? String, at: time, days: points("daily")),
                temperature: temperature, feelsLike: JSON.double(hour["apparentTemperature"]), precipitationChance: percent(hour["precipProbability"]),
                // An hour at so many millimeters an hour, of liquid water.
                precipitation: JSON.double(hour["precipIntensity"]), pressure: JSON.double(hour["pressure"]),
                uvIndex: JSON.double(hour["uvIndex"]), windSpeed: JSON.double(hour["windSpeed"]))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        report.daily = points("daily").compactMap { day -> WeatherReport.Day? in
            guard let time = JSON.double(day["time"]), let high = JSON.double(day["temperatureMax"] ?? day["temperatureHigh"]),
                  let low = JSON.double(day["temperatureMin"] ?? day["temperatureLow"]) else { return nil }
            return WeatherReport.Day(
                date: calendar.startOfDay(for: Date(timeIntervalSince1970: time + 12 * 3600)), condition: condition(day), high: high, low: low,
                precipitationChance: percent(day["precipProbability"]),
                // The day's average liquid-water rate, over its 24 hours.
                precipitation: JSON.double(day["precipIntensity"]).map { $0 * 24 },
                sunrise: JSON.double(day["sunriseTime"]).map(Date.init(timeIntervalSince1970:)),
                sunset: JSON.double(day["sunsetTime"]).map(Date.init(timeIntervalSince1970:)),
                uvIndexMax: JSON.double(day["uvIndex"]), windSpeedMax: JSON.double(day["windSpeed"]))
        }
        // With SI units the index is Europe's 0–100 scale.
        let pm25 = JSON.double(now["pm25"]), pm10 = JSON.double(now["pm10"])
        if let index = JSON.int(now["airQualityIndex"]) {
            report.air = .init(usIndex: WeatherReport.AirQuality.usIndex(pm25: pm25, pm10: pm10), europeanIndex: index, pm25: pm25, pm10: pm10)
        }
        report.alerts = ((json["alerts"] as? [[String: Any]]) ?? []).compactMap { alert -> WeatherAlert? in
            guard let title = alert["title"] as? String else { return nil }
            let expires = JSON.double(alert["expires"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            if let expires, expires < fetched { return nil }
            return WeatherAlert(title: title, severity: .init(alert["severity"] as? String),
                                starts: JSON.double(alert["time"]).map(Date.init(timeIntervalSince1970:)), ends: expires,
                                detail: alert["description"] as? String, source: (alert["regions"] as? [String])?.first,
                                url: (alert["uri"] as? String).flatMap(URL.init(string:)))
        }
        .sorted { $0.severity > $1.severity }
        return report
    }

    /// Night icons say so; otherwise, whether it's between sunrise and sunset on its day. (Each day's
    /// `time` is its local midnight.)
    private static func isDay(_ icon: String?, at time: Double, days: [[String: Any]]) -> Bool {
        if let icon, icon.hasSuffix("-night") { return false }
        if let icon, icon.hasSuffix("-day") { return true }
        guard let day = days.first(where: { JSON.double($0["time"]).map { (($0) ..< $0 + 86400).contains(time) } == true }),
              let sunrise = JSON.double(day["sunriseTime"]), let sunset = JSON.double(day["sunsetTime"]) else { return true }
        return time >= sunrise && time < sunset
    }

    /// From a data point's icon, and its rain's type and rate.
    static func condition(_ point: [String: Any]) -> WeatherCondition {
        let icon = point["icon"] as? String ?? ""
        let type = point["precipType"] as? String
        let rate = JSON.double(point["precipIntensity"]) ?? 0
        switch icon {
        case "clear-day", "clear-night": return .clear
        case "mostly-clear-day", "mostly-clear-night": return .mostlyClear
        case "partly-cloudy-day", "partly-cloudy-night": return .partlyCloudy
        case "cloudy", "mostly-cloudy-day", "mostly-cloudy-night": return .cloudy
        case "fog", "mist": return .fog
        case "haze", "smoke": return .haze
        case "wind", "breezy", "dangerous-wind": return .windy
        case "drizzle": return .drizzle
        case "heavy-rain": return .heavyRain
        case "rain", "light-rain", "precipitation", "possible-rain-day", "possible-rain-night", "possible-precipitation-day", "possible-precipitation-night":
            if type == "ice" { return .freezingRain }
            // 7.6 mm an hour is where rain is called heavy.
            return rate >= 7.6 ? .heavyRain : .rain
        case "heavy-snow": return .heavySnow
        case "snow", "flurries", "light-snow", "possible-snow-day", "possible-snow-night": return .snow
        case "sleet", "mixed", "very-light-sleet", "light-sleet", "heavy-sleet", "possible-sleet-day", "possible-sleet-night":
            return type == "ice" ? .freezingRain : .sleet
        case "thunderstorm", "possible-thunderstorm-day", "possible-thunderstorm-night": return .thunderstorm
        case "hail": return .hail
        default: return .cloudy
        }
    }
}

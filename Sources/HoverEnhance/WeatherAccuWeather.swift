import Foundation

/// AccuWeather's Core Weather API, with the user's key: the place's location key, looked up once per
/// place, then current conditions and the 12-hour and 5-day forecasts, which are what its cheapest plan
/// includes. Alerts and minute-by-minute rain need dearer plans, so US alerts come from the NWS. The key
/// goes in a header rather than the URL.
struct AccuWeather: WeatherSource {
    private static let base = "https://dataservice.accuweather.com/"

    /// Where location keys are kept.
    var locations = AccuWeatherLocations.shared

    static func request(_ path: String, _ items: [String: String] = [:], key: String) -> URLRequest? {
        // A header can't carry spaces or control characters, and no key has them.
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { return nil }
        var request = URLComponents.request(base + path, items)
        request?.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func locationRequest(at coordinate: Coordinate, key: String) -> URLRequest? {
        request("locations/v1/cities/geoposition/search", ["q": coordinate.query], key: key)
    }

    /// The forecasts for a location key: "currentconditions/v1", "forecasts/v1/hourly/12hour", or
    /// "forecasts/v1/daily/5day".
    static func request(_ path: String, for location: String, key: String) -> URLRequest? {
        // The location key came from AccuWeather; encoded anyway, so it can only ever be one path segment.
        guard let segment = location.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        // Current conditions always come in both unit systems; forecasts come in the one asked for.
        let items = path.hasPrefix("forecasts") ? ["details": "true", "metric": "true"] : ["details": "true"]
        return request("\(path)/\(segment)", items, key: key)
    }

    func report(at coordinate: Coordinate, key: String?, timeZone: TimeZone, using http: any WeatherHTTP) async throws(WeatherError) -> WeatherReport {
        guard let key, !key.isEmpty else { throw .needsKey }
        let location = try await location(at: coordinate, key: key, using: http)
        guard let current = Self.request("currentconditions/v1", for: location.key, key: key),
              let hourly = Self.request("forecasts/v1/hourly/12hour", for: location.key, key: key),
              let daily = Self.request("forecasts/v1/daily/5day", for: location.key, key: key) else { throw .badKey }
        async let hourlyData = http.result(for: hourly)
        async let dailyData = http.result(for: daily)
        let currentData = try await http.data(for: current)
        return try Self.report(current: currentData, hourly: await hourlyData.get(), daily: await dailyData.get(),
                               timeZone: location.timeZone ?? timeZone, fetched: Date())
    }

    private func location(at coordinate: Coordinate, key: String, using http: any WeatherHTTP) async throws(WeatherError) -> AccuWeatherLocations.Location {
        if let known = await locations.location(at: coordinate) { return known }
        guard let request = Self.locationRequest(at: coordinate, key: key) else { throw .badKey }
        let location = try Self.location(from: await http.data(for: request))
        await locations.keep(location, at: coordinate)
        return location
    }

    static func location(from data: Data) throws(WeatherError) -> AccuWeatherLocations.Location {
        let json = try JSON.object(data)
        guard let key = json["Key"] as? String, !key.isEmpty else { throw .unreadable }
        let zone = (json["TimeZone"] as? [String: Any])?["Name"] as? String
        return .init(key: key, timeZone: zone.flatMap(TimeZone.init(identifier:)))
    }

    static func report(current: Data, hourly: Data, daily: Data, timeZone: TimeZone, fetched: Date) throws(WeatherError) -> WeatherReport {
        // Current conditions come as a list of one.
        guard let now = (try? JSONSerialization.jsonObject(with: current) as? [[String: Any]])?.first,
              let temperature = metric(now["Temperature"]), let time = JSON.double(now["EpochTime"]) else { throw .unreadable }
        let wind = now["Wind"] as? [String: Any]

        var report = WeatherReport(provider: .accuWeather, fetched: fetched, timeZone: timeZone, current: .init(
            time: Date(timeIntervalSince1970: time),
            condition: condition(JSON.int(now["WeatherIcon"])),
            isDay: now["IsDayTime"] as? Bool ?? true,
            temperature: temperature,
            feelsLike: metric(now["RealFeelTemperature"]),
            feelsLikeInShade: metric(now["RealFeelTemperatureShade"]),
            humidity: JSON.double(now["RelativeHumidity"]),
            dewPoint: metric(now["DewPoint"]),
            pressure: metric(now["Pressure"]),
            pressureTendency: pressureTendency((now["PressureTendency"] as? [String: Any])?["Code"] as? String),
            windSpeed: speed(wind),
            windGust: speed(now["WindGust"] as? [String: Any]),
            windDirection: JSON.double((wind?["Direction"] as? [String: Any])?["Degrees"]),
            visibility: metric(now["Visibility"]),
            uvIndex: JSON.double(now["UVIndexFloat"]) ?? JSON.double(now["UVIndex"]),
            cloudCover: JSON.double(now["CloudCover"]),
            precipitation: metric(now["Precip1hr"]),
            changeSinceYesterday: metric(now["Past24HourTemperatureDeparture"]),
            precipitationLast24Hours: metric((now["PrecipitationSummary"] as? [String: Any])?["Past24Hours"])
        ))
        report.link = link(now["Link"] as? String)

        guard let hours = try? JSONSerialization.jsonObject(with: hourly) as? [[String: Any]] else { throw .unreadable }
        report.hourly = hours.compactMap { hour -> WeatherReport.Hour? in
            guard let time = JSON.double(hour["EpochDateTime"]), let temperature = metric(hour["Temperature"]) else { return nil }
            return WeatherReport.Hour(
                time: Date(timeIntervalSince1970: time), condition: condition(JSON.int(hour["WeatherIcon"]), intensity: hour["PrecipitationIntensity"] as? String),
                isDay: hour["IsDaylight"] as? Bool ?? true, temperature: temperature, feelsLike: metric(hour["RealFeelTemperature"]),
                precipitationChance: JSON.double(hour["PrecipitationProbability"]), precipitation: metric(hour["TotalLiquid"]),
                uvIndex: JSON.double(hour["UVIndexFloat"]) ?? JSON.double(hour["UVIndex"]), windSpeed: speed(hour["Wind"] as? [String: Any]))
        }

        let forecast = try JSON.object(daily)
        report.summary = ((forecast["Headline"] as? [String: Any])?["Text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = (forecast["DailyForecasts"] as? [[String: Any]]) ?? []
        report.daily = days.compactMap { entry -> WeatherReport.Day? in
            guard let time = JSON.double(entry["EpochDate"]), let range = entry["Temperature"] as? [String: Any],
                  let high = metric(range["Maximum"]), let low = metric(range["Minimum"]) else { return nil }
            // Day runs sunrise to sunset, and night on to the next sunrise.
            let parts = [entry["Day"], entry["Night"]].compactMap { $0 as? [String: Any] }
            let day = parts.first
            let sun = entry["Sun"] as? [String: Any]
            let amounts = parts.compactMap { metric($0["TotalLiquid"]) }
            return WeatherReport.Day(
                date: calendar.startOfDay(for: Date(timeIntervalSince1970: time)),
                condition: condition(JSON.int(day?["Icon"]), intensity: day?["PrecipitationIntensity"] as? String), high: high, low: low,
                precipitationChance: parts.compactMap { JSON.double($0["PrecipitationProbability"]) }.max(),
                precipitation: amounts.isEmpty ? nil : amounts.reduce(0, +),
                sunrise: JSON.double(sun?["EpochRise"]).map(Date.init(timeIntervalSince1970:)),
                sunset: JSON.double(sun?["EpochSet"]).map(Date.init(timeIntervalSince1970:)),
                uvIndexMax: airAndPollen(entry)["uvindex"].flatMap { JSON.double($0["Value"]) },
                windSpeedMax: parts.compactMap { speed($0["Wind"] as? [String: Any]) }.max())
        }

        // Air and pollen are forecast by the day: today's stand for now.
        let today = days.first { JSON.double($0["EpochDate"]).map { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: fetched) } == true }
        let readings = today.map(airAndPollen) ?? [:]
        if let air = readings["airquality"], let rating = rating(air) {
            report.air = .init(rating: rating, mainPollutant: (air["Type"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
        report.pollen = WeatherReport.Pollen.Kind.allCases.compactMap { kind in
            guard let reading = readings[kind.rawValue], let rating = rating(reading) else { return nil }
            return .init(kind: kind, rating: rating)
        }
        return report
    }

    /// A measure in metric: `{"Value": 12.3, "Unit": "C"}`, as forecasts asked for in metric give it, or
    /// `{"Metric": {…}, "Imperial": {…}}`, as current conditions do.
    static func metric(_ object: Any?) -> Double? {
        guard let object = object as? [String: Any] else { return nil }
        return JSON.double((object["Metric"] as? [String: Any])?["Value"] ?? object["Value"])
    }

    /// Meters per second, from a wind's speed in km/h.
    private static func speed(_ wind: [String: Any]?) -> Double? {
        metric(wind?["Speed"]).map { $0 / 3.6 }
    }

    /// A day's air quality, pollen, and UV readings, by lowercased name.
    private static func airAndPollen(_ day: [String: Any]) -> [String: [String: Any]] {
        let readings = (day["AirAndPollen"] as? [[String: Any]]) ?? []
        return Dictionary(readings.compactMap { reading in (reading["Name"] as? String).map { ($0.lowercased(), reading) } }) { first, _ in first }
    }

    /// A reading's category, "Very High" written "Very high", with its 1-to-6 value counted from 0.
    private static func rating(_ reading: [String: Any]) -> WeatherReport.Rating? {
        guard let name = reading["Category"] as? String, let first = name.first, let value = JSON.int(reading["CategoryValue"]) else { return nil }
        return .init(name: first.uppercased() + name.dropFirst().lowercased(), level: min(max(value - 1, 0), 5))
    }

    private static func pressureTendency(_ code: String?) -> WeatherReport.PressureTrend? {
        switch code {
        case "R": .rising
        case "S": .steady
        case "F": .falling
        default: nil
        }
    }

    /// The place's page on AccuWeather, over HTTPS (it's given as plain HTTP).
    private static func link(_ text: String?) -> URL? {
        guard var components = text.flatMap(URLComponents.init(string:)), components.host?.hasSuffix("accuweather.com") == true else { return nil }
        components.scheme = "https"
        return components.url
    }

    /// AccuWeather's icon numbers, and how hard rain or snow is falling where it's forecast.
    static func condition(_ icon: Int?, intensity: String? = nil) -> WeatherCondition {
        let heavy = intensity?.lowercased() == "heavy"
        switch icon {
        case 1, 30, 31, 33: return .clear
        case 2, 34: return .mostlyClear
        case 3, 4, 35, 36: return .partlyCloudy
        case 5, 37: return .haze
        case 11: return .fog
        case 12, 13, 14, 18, 39, 40: return heavy ? .heavyRain : .rain
        case 15, 16, 17, 41, 42: return .thunderstorm
        case 19, 20, 21, 22, 23, 43, 44: return heavy ? .heavySnow : .snow
        case 24, 26: return .freezingRain
        case 25, 29: return .sleet
        case 32: return .windy
        default: return .cloudy
        }
    }
}

/// AccuWeather's keys for places, by coordinate. A place's key doesn't change, and each lookup counts
/// against the plan, so each is looked up once while HoverEnhance runs.
actor AccuWeatherLocations {
    static let shared = AccuWeatherLocations()

    struct Location: Sendable, Equatable {
        var key: String
        var timeZone: TimeZone?
    }

    private var known: [Coordinate: Location] = [:]

    func location(at coordinate: Coordinate) -> Location? { known[coordinate.rounded] }

    func keep(_ location: Location, at coordinate: Coordinate) { known[coordinate.rounded] = location }
}

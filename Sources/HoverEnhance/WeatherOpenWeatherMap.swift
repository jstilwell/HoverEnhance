import Foundation

/// OpenWeatherMap's free APIs, with the user's key: current weather, a 5-day forecast in 3-hour steps,
/// and air pollution. (One Call 3.0 needs a separate subscription, so it isn't used.)
struct OpenWeatherMap: WeatherSource {
    private static let base = "https://api.openweathermap.org/data/2.5/"

    static func request(_ path: String, at coordinate: Coordinate, key: String) -> URLRequest? {
        URLComponents.request(base + path, [
            "lat": String(format: "%.2f", coordinate.latitude),
            "lon": String(format: "%.2f", coordinate.longitude),
            "units": "metric",
            "appid": key,
        ])
    }

    func report(at coordinate: Coordinate, key: String?, timeZone: TimeZone, using http: any WeatherHTTP) async throws(WeatherError) -> WeatherReport {
        guard let key, let current = Self.request("weather", at: coordinate, key: key),
              let forecast = Self.request("forecast", at: coordinate, key: key),
              let air = Self.request("air_pollution", at: coordinate, key: key) else { throw .needsKey }
        async let forecastData = http.result(for: forecast)
        async let airData: Data? = { try? await http.data(for: air) }()
        let currentData = try await http.data(for: current)
        return try Self.report(current: currentData, forecast: await forecastData.get(), air: await airData, timeZone: timeZone, fetched: Date())
    }

    static func report(current: Data, forecast: Data, air: Data?, timeZone place: TimeZone, fetched: Date) throws(WeatherError) -> WeatherReport {
        let now = try JSON.object(current)
        guard let main = now["main"] as? [String: Any], let temperature = JSON.double(main["temp"]), let time = JSON.double(now["dt"]) else {
            throw .unreadable
        }
        // Only an offset is given; the place's own zone is better when it agrees, as it knows daylight saving.
        let offset = JSON.int(now["timezone"])
        let timeZone = offset.map { place.secondsFromGMT(for: Date(timeIntervalSince1970: time)) == $0 } == false
            ? offset.flatMap(TimeZone.init(secondsFromGMT:)) ?? place : place
        let weather = (now["weather"] as? [[String: Any]])?.first
        let wind = now["wind"] as? [String: Any]
        let humidity = JSON.double(main["humidity"])
        let rain = ((now["rain"] as? [String: Any]).flatMap { JSON.double($0["1h"]) } ?? 0) + ((now["snow"] as? [String: Any]).flatMap { JSON.double($0["1h"]) } ?? 0)

        var report = WeatherReport(provider: .openWeatherMap, fetched: fetched, timeZone: timeZone, current: .init(
            time: Date(timeIntervalSince1970: time),
            condition: condition(JSON.int(weather?["id"])),
            isDay: (weather?["icon"] as? String)?.hasSuffix("n") != true,
            temperature: temperature,
            feelsLike: JSON.double(main["feels_like"]),
            humidity: humidity,
            dewPoint: humidity.map { WeatherMath.dewPoint(temperature: temperature, humidity: $0) },
            pressure: JSON.double(main["sea_level"]) ?? JSON.double(main["pressure"]),
            windSpeed: JSON.double(wind?["speed"]),
            windGust: JSON.double(wind?["gust"]),
            windDirection: JSON.double(wind?["deg"]),
            visibility: JSON.double(now["visibility"]).map { $0 / 1000 },
            cloudCover: (now["clouds"] as? [String: Any]).flatMap { JSON.double($0["all"]) },
            precipitation: rain
        ))

        // Each step with its own high and low, read together, so a step that's skipped can't shift the rest.
        let steps = ((try JSON.object(forecast)["list"] as? [[String: Any]]) ?? []).compactMap { step -> (hour: WeatherReport.Hour, high: Double, low: Double)? in
            guard let main = step["main"] as? [String: Any], let temperature = JSON.double(main["temp"]), let time = JSON.double(step["dt"]) else { return nil }
            let amount = ((step["rain"] as? [String: Any]).flatMap { JSON.double($0["3h"]) } ?? 0)
                + ((step["snow"] as? [String: Any]).flatMap { JSON.double($0["3h"]) } ?? 0)
            let hour = WeatherReport.Hour(
                time: Date(timeIntervalSince1970: time), condition: condition(JSON.int((step["weather"] as? [[String: Any]])?.first?["id"])),
                isDay: (step["sys"] as? [String: Any])?["pod"] as? String != "n", temperature: temperature, feelsLike: JSON.double(main["feels_like"]),
                precipitationChance: JSON.double(step["pop"]).map { $0 * 100 }, precipitation: amount,
                pressure: JSON.double(main["sea_level"]) ?? JSON.double(main["pressure"]),
                windSpeed: JSON.double((step["wind"] as? [String: Any])?["speed"]))
            return (hour, JSON.double(main["temp_max"]) ?? temperature, JSON.double(main["temp_min"]) ?? temperature)
        }
        report.hourly = steps.map(\.hour)
        report.daily = days(from: steps, timeZone: timeZone, sun: now["sys"] as? [String: Any], today: Date(timeIntervalSince1970: time))

        if let air, let entry = (try? JSON.object(air))?["list"] as? [[String: Any]], let components = entry.first?["components"] as? [String: Any] {
            let pm25 = JSON.double(components["pm2_5"]), pm10 = JSON.double(components["pm10"])
            report.air = .init(usIndex: WeatherReport.AirQuality.usIndex(pm25: pm25, pm10: pm10), pm25: pm25, pm10: pm10,
                               ozone: JSON.double(components["o3"]), nitrogenDioxide: JSON.double(components["no2"]))
        }
        return report
    }

    /// Days from the 3-hour steps, by the place's calendar: their highest and lowest, their worst daytime
    /// weather, and the day's chance and amount of rain. A last day with only a few steps left is dropped.
    private static func days(from steps: [(hour: WeatherReport.Hour, high: Double, low: Double)], timeZone: TimeZone, sun: [String: Any]?,
                             today: Date) -> [WeatherReport.Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let byDay = Dictionary(grouping: steps) { calendar.startOfDay(for: $0.hour.time) }
        let startOfToday = calendar.startOfDay(for: today)
        return byDay.keys.sorted().compactMap { day -> WeatherReport.Day? in
            guard let entries = byDay[day], entries.count >= 3 || day == startOfToday else { return nil }
            let daytime = entries.filter(\.hour.isDay)
            let isToday = day == startOfToday
            return WeatherReport.Day(
                date: day, condition: WeatherCondition.worst((daytime.isEmpty ? entries : daytime).map(\.hour.condition)),
                high: entries.map(\.high).max() ?? 0, low: entries.map(\.low).min() ?? 0,
                precipitationChance: entries.compactMap(\.hour.precipitationChance).max(),
                precipitation: entries.compactMap(\.hour.precipitation).reduce(0, +),
                sunrise: isToday ? JSON.double(sun?["sunrise"]).map(Date.init(timeIntervalSince1970:)) : nil,
                sunset: isToday ? JSON.double(sun?["sunset"]).map(Date.init(timeIntervalSince1970:)) : nil)
        }
    }

    /// OpenWeatherMap's condition codes.
    static func condition(_ code: Int?) -> WeatherCondition {
        switch code ?? 803 {
        case 200 ..< 300: .thunderstorm
        case 300 ..< 400: .drizzle
        case 502 ... 504, 522: .heavyRain
        case 511: .freezingRain
        case 500 ..< 600: .rain
        case 602, 622: .heavySnow
        case 611 ... 616: .sleet
        case 600 ..< 700: .snow
        case 701, 741: .fog
        case 711, 721, 731, 751, 761, 762: .haze
        case 771, 781: .windy
        case 800: .clear
        case 801: .mostlyClear
        case 802: .partlyCloudy
        default: .cloudy
        }
    }
}

enum WeatherMath {
    /// The dew point, by the Magnus formula, from degrees Celsius and relative humidity in percent.
    static func dewPoint(temperature: Double, humidity: Double) -> Double {
        let a = 17.62, b = 243.12
        let gamma = Foundation.log(max(humidity, 1) / 100) + a * temperature / (b + temperature)
        return b * gamma / (a - gamma)
    }
}

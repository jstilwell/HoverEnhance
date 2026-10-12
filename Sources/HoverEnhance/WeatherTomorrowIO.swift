import Foundation

/// Tomorrow.io v4, with the user's key: the forecast (minutely where the plan has it, hourly, daily) and
/// realtime conditions. Its answers carry no time zone and no day or night, so the place's zone and each
/// day's sunrise and sunset stand in.
struct TomorrowIO: WeatherSource {
    static func request(_ path: String, at coordinate: Coordinate, key: String) -> URLRequest? {
        URLComponents.request("https://api.tomorrow.io/v4/weather/" + path, ["location": coordinate.query, "units": "metric", "apikey": key])
    }

    func report(at coordinate: Coordinate, key: String?, timeZone: TimeZone, using http: any WeatherHTTP) async throws(WeatherError) -> WeatherReport {
        guard let key, let forecast = Self.request("forecast", at: coordinate, key: key), let realtime = Self.request("realtime", at: coordinate, key: key) else {
            throw .needsKey
        }
        // Realtime is better for now, but the forecast covers it if realtime doesn't come.
        async let now: Data? = { try? await http.data(for: realtime) }()
        let forecastData = try await http.data(for: forecast)
        return try Self.report(forecast: forecastData, realtime: await now, timeZone: timeZone, fetched: Date())
    }

    static func report(forecast: Data, realtime: Data?, timeZone: TimeZone, fetched: Date) throws(WeatherError) -> WeatherReport {
        guard let timelines = try JSON.object(forecast)["timelines"] as? [String: Any] else { throw .unreadable }
        func entries(_ name: String) -> [(time: Date, values: [String: Any])] {
            ((timelines[name] as? [[String: Any]]) ?? []).compactMap { entry in
                guard let time = JSON.date(entry["time"]), let values = entry["values"] as? [String: Any] else { return nil }
                return (time, values)
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        // Days run 6 am to 6 am, stamped with the 6 am that starts them.
        let daily = entries("daily").compactMap { time, values -> WeatherReport.Day? in
            guard let high = JSON.double(values["temperatureMax"]), let low = JSON.double(values["temperatureMin"]) else { return nil }
            let amount = ["rainAccumulationSum", "snowAccumulationLweSum", "sleetAccumulationLweSum", "iceAccumulationLweSum"]
                .compactMap { JSON.double(values[$0]) }
            return WeatherReport.Day(
                date: calendar.startOfDay(for: time), condition: condition(JSON.int(values["weatherCodeMax"])), high: high, low: low,
                precipitationChance: JSON.double(values["precipitationProbabilityMax"]),
                precipitation: amount.isEmpty ? nil : amount.reduce(0, +),
                sunrise: JSON.date(values["sunriseTime"]), sunset: JSON.date(values["sunsetTime"]),
                uvIndexMax: JSON.double(values["uvIndexMax"]), windSpeedMax: JSON.double(values["windSpeedMax"]))
        }
        func isDay(_ time: Date) -> Bool {
            if let day = daily.first(where: { calendar.isDate($0.date, inSameDayAs: time) }), let sunrise = day.sunrise, let sunset = day.sunset {
                return time >= sunrise && time < sunset
            }
            return (6 ..< 18).contains(calendar.component(.hour, from: time))
        }
        let hourly = entries("hourly").compactMap { time, values -> WeatherReport.Hour? in
            guard let temperature = JSON.double(values["temperature"]) else { return nil }
            let amount = ["rainAccumulation", "snowAccumulationLwe", "sleetAccumulationLwe", "iceAccumulationLwe"].compactMap { JSON.double(values[$0]) }
            return WeatherReport.Hour(
                time: time, condition: condition(JSON.int(values["weatherCode"])), isDay: isDay(time), temperature: temperature,
                feelsLike: JSON.double(values["temperatureApparent"]), precipitationChance: JSON.double(values["precipitationProbability"]),
                precipitation: amount.isEmpty ? nil : amount.reduce(0, +), pressure: JSON.double(values["pressureSeaLevel"]),
                uvIndex: JSON.double(values["uvIndex"]), windSpeed: JSON.double(values["windSpeed"]))
        }
        let minutely = entries("minutely").map { time, values in
            WeatherReport.Minute(
                time: time, intensity: ["rainIntensity", "snowIntensity", "sleetIntensity", "freezingRainIntensity"].compactMap { JSON.double(values[$0]) }.reduce(0, +),
                chance: JSON.double(values["precipitationProbability"]))
        }

        // Now: realtime's values, or else the hour under way.
        let realtimeData = realtime.flatMap { try? JSON.object($0) }?["data"] as? [String: Any]
        let thisHour = entries("hourly").last { $0.time <= fetched }
        guard let (time, values) = realtimeData.flatMap({ data in JSON.date(data["time"]).flatMap { time in (data["values"] as? [String: Any]).map { (time, $0) } } })
                ?? thisHour ?? entries("hourly").first,
              let temperature = JSON.double(values["temperature"]) else { throw .unreadable }
        let intensity = ["rainIntensity", "snowIntensity", "sleetIntensity", "freezingRainIntensity"].compactMap { JSON.double(values[$0]) }
        var report = WeatherReport(provider: .tomorrow, fetched: fetched, timeZone: timeZone, current: .init(
            time: time,
            condition: condition(JSON.int(values["weatherCode"])),
            isDay: isDay(time),
            temperature: temperature,
            feelsLike: JSON.double(values["temperatureApparent"]),
            humidity: JSON.double(values["humidity"]),
            dewPoint: JSON.double(values["dewPoint"]),
            // Realtime gives only surface pressure, which falls with altitude; the hour's sea-level pressure compares.
            pressure: JSON.double(values["pressureSeaLevel"]) ?? thisHour.flatMap { JSON.double($0.values["pressureSeaLevel"]) },
            windSpeed: JSON.double(values["windSpeed"]),
            windGust: JSON.double(values["windGust"]),
            windDirection: JSON.double(values["windDirection"]),
            visibility: JSON.double(values["visibility"]),
            uvIndex: JSON.double(values["uvIndex"]),
            cloudCover: JSON.double(values["cloudCover"]),
            precipitation: intensity.isEmpty ? nil : intensity.reduce(0, +)
        ))
        report.hourly = hourly
        report.daily = daily
        report.minutely = minutely
        return report
    }

    /// Tomorrow.io's weather codes: the four-digit ones its forecasts use, and the mixed ones of its
    /// day-part codes (which come ten times larger, plus a day or night digit).
    static func condition(_ code: Int?) -> WeatherCondition {
        var code = code ?? 0
        if code >= 10000 { code /= 10 }
        switch code {
        case 1000: return .clear
        case 1100: return .mostlyClear
        case 1101, 1103: return .partlyCloudy
        case 1001, 1102: return .cloudy
        case 2000 ..< 3000: return .fog
        case 4000, 4203 ... 4205: return .drizzle
        case 4201, 4202, 4211, 4212: return .heavyRain
        case 4000 ..< 5000: return .rain
        case 5101, 5119 ... 5121: return .heavySnow
        case 5108, 5110, 5112, 5122: return .sleet
        case 5114: return .freezingRain
        case 5000 ..< 6000: return .snow
        case 6000 ..< 7000, 7103, 7106: return .freezingRain
        case 7000 ..< 8000: return .sleet
        case 8000 ..< 9000: return .thunderstorm
        default: return .cloudy
        }
    }
}

import Foundation

/// WeatherAPI.com, with the user's key: one forecast request with air quality and alerts. The free plan
/// gives three days. Every value comes in both unit systems; the metric ones are read.
struct WeatherAPIcom: WeatherSource {
    static func request(at coordinate: Coordinate, key: String) -> URLRequest? {
        URLComponents.request("https://api.weatherapi.com/v1/forecast.json", [
            "key": key, "q": coordinate.query, "days": "3", "aqi": "yes", "alerts": "yes",
        ])
    }

    func report(at coordinate: Coordinate, key: String?, timeZone: TimeZone, using http: any WeatherHTTP) async throws(WeatherError) -> WeatherReport {
        guard let key, let request = Self.request(at: coordinate, key: key) else { throw .needsKey }
        return try Self.report(from: await http.data(for: request), timeZone: timeZone, fetched: Date())
    }

    static func report(from data: Data, timeZone place: TimeZone, fetched: Date) throws(WeatherError) -> WeatherReport {
        let json = try JSON.object(data)
        guard let now = json["current"] as? [String: Any], let temperature = JSON.double(now["temp_c"]) else { throw .unreadable }
        let timeZone = ((json["location"] as? [String: Any])?["tz_id"] as? String).flatMap(TimeZone.init(identifier:)) ?? place
        func speed(_ kph: Any?) -> Double? { JSON.double(kph).map { $0 / 3.6 } }

        var report = WeatherReport(provider: .weatherAPI, fetched: fetched, timeZone: timeZone, current: .init(
            time: JSON.double(now["last_updated_epoch"]).map(Date.init(timeIntervalSince1970:)) ?? fetched,
            condition: condition(JSON.int((now["condition"] as? [String: Any])?["code"])),
            isDay: JSON.int(now["is_day"]) != 0,
            temperature: temperature,
            feelsLike: JSON.double(now["feelslike_c"]),
            humidity: JSON.double(now["humidity"]),
            dewPoint: JSON.double(now["dewpoint_c"]),
            pressure: JSON.double(now["pressure_mb"]),
            windSpeed: speed(now["wind_kph"]),
            windGust: speed(now["gust_kph"]),
            windDirection: JSON.double(now["wind_degree"]),
            visibility: JSON.double(now["vis_km"]),
            uvIndex: JSON.double(now["uv"]),
            cloudCover: JSON.double(now["cloud"]),
            precipitation: JSON.double(now["precip_mm"])
        ))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = ((json["forecast"] as? [String: Any])?["forecastday"] as? [[String: Any]]) ?? []
        report.hourly = days.flatMap { ($0["hour"] as? [[String: Any]]) ?? [] }.compactMap { hour -> WeatherReport.Hour? in
            guard let time = JSON.double(hour["time_epoch"]), let temperature = JSON.double(hour["temp_c"]) else { return nil }
            return WeatherReport.Hour(
                time: Date(timeIntervalSince1970: time), condition: condition(JSON.int((hour["condition"] as? [String: Any])?["code"])),
                isDay: JSON.int(hour["is_day"]) != 0, temperature: temperature, feelsLike: JSON.double(hour["feelslike_c"]),
                precipitationChance: [JSON.double(hour["chance_of_rain"]), JSON.double(hour["chance_of_snow"])].compactMap { $0 }.max(),
                precipitation: JSON.double(hour["precip_mm"]), pressure: JSON.double(hour["pressure_mb"]),
                uvIndex: JSON.double(hour["uv"]), windSpeed: speed(hour["wind_kph"]))
        }
        report.daily = days.compactMap { entry -> WeatherReport.Day? in
            guard let dateText = entry["date"] as? String, let date = dayFormatter(timeZone).date(from: dateText),
                  let day = entry["day"] as? [String: Any], let high = JSON.double(day["maxtemp_c"]), let low = JSON.double(day["mintemp_c"]) else { return nil }
            let astro = entry["astro"] as? [String: Any]
            func sun(_ key: String) -> Date? {
                (astro?[key] as? String).flatMap { timeFormatter(timeZone).date(from: "\(dateText) \($0)") }
            }
            return WeatherReport.Day(
                date: calendar.startOfDay(for: date), condition: condition(JSON.int((day["condition"] as? [String: Any])?["code"])), high: high, low: low,
                precipitationChance: [JSON.double(day["daily_chance_of_rain"]), JSON.double(day["daily_chance_of_snow"])].compactMap { $0 }.max(),
                precipitation: JSON.double(day["totalprecip_mm"]), sunrise: sun("sunrise"), sunset: sun("sunset"),
                uvIndexMax: JSON.double(day["uv"]), windSpeedMax: speed(day["maxwind_kph"]))
        }

        if let air = now["air_quality"] as? [String: Any] {
            let pm25 = JSON.double(air["pm2_5"]), pm10 = JSON.double(air["pm10"])
            // Its `us-epa-index` is the category (1 to 6), not the index; the index comes from the amounts.
            report.air = .init(usIndex: WeatherReport.AirQuality.usIndex(pm25: pm25, pm10: pm10), pm25: pm25, pm10: pm10,
                               ozone: JSON.double(air["o3"]), nitrogenDioxide: JSON.double(air["no2"]))
        }

        var seen = Set<String>()
        report.alerts = (((json["alerts"] as? [String: Any])?["alert"] as? [[String: Any]]) ?? []).compactMap { alert -> WeatherAlert? in
            guard let title = (alert["event"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? alert["headline"] as? String else { return nil }
            let ends = JSON.date(alert["expires"])
            if let ends, ends < fetched { return nil }
            guard seen.insert("\(title)|\(ends?.timeIntervalSince1970 ?? 0)").inserted else { return nil }
            return WeatherAlert(title: title, severity: .init(alert["severity"] as? String), starts: JSON.date(alert["effective"]), ends: ends,
                                detail: alert["desc"] as? String, source: alert["areas"] as? String)
        }
        .sorted { $0.severity > $1.severity }
        return report
    }

    /// "2026-03-22", a day in the place's calendar.
    private static func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// "2026-03-22 06:03 AM", a sunrise or sunset in local time. "No sunrise" and the like don't parse.
    private static func timeFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd hh:mm a"
        return formatter
    }

    /// WeatherAPI.com's condition codes.
    static func condition(_ code: Int?) -> WeatherCondition {
        switch code {
        case 1000: .clear
        case 1003: .partlyCloudy
        case 1006, 1009: .cloudy
        case 1012, 1015, 1033, 1036, 1039, 1042, 1045, 1048: .haze
        case 1018, 1021, 1024, 1027: .windy
        case 1030, 1135, 1147: .fog
        case 1150, 1153: .drizzle
        case 1072, 1168, 1171, 1198, 1201: .freezingRain
        case 1063, 1180, 1183, 1186, 1189, 1240, 1243: .rain
        case 1192, 1195, 1246: .heavyRain
        case 1069, 1204, 1207, 1237, 1249, 1252, 1261, 1264: .sleet
        case 1066, 1114, 1210, 1213, 1216, 1219, 1255, 1258: .snow
        case 1117, 1222, 1225: .heavySnow
        case 1087, 1273, 1276, 1279, 1282: .thunderstorm
        default: .cloudy
        }
    }
}

import Foundation

/// Open-Meteo: free, with no key, for non-commercial use. A forecast request and an air quality request,
/// both asked for in metric units with times as Unix seconds.
struct OpenMeteo: WeatherSource {
    static func forecastRequest(at coordinate: Coordinate) -> URLRequest? {
        URLComponents.request("https://api.open-meteo.com/v1/forecast", [
            "latitude": String(format: "%.2f", coordinate.latitude),
            "longitude": String(format: "%.2f", coordinate.longitude),
            "current": "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,cloud_cover,pressure_msl,"
                + "wind_speed_10m,wind_direction_10m,wind_gusts_10m,dew_point_2m,visibility,uv_index",
            "hourly": "temperature_2m,apparent_temperature,weather_code,precipitation_probability,precipitation,is_day,pressure_msl,uv_index,wind_speed_10m",
            "minutely_15": "precipitation",
            "forecast_minutely_15": "8",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset,"
                + "uv_index_max,wind_speed_10m_max",
            "timezone": "auto",
            "timeformat": "unixtime",
            "forecast_days": "10",
            "wind_speed_unit": "ms",
        ])
    }

    static func airRequest(at coordinate: Coordinate) -> URLRequest? {
        URLComponents.request("https://air-quality-api.open-meteo.com/v1/air-quality", [
            "latitude": String(format: "%.2f", coordinate.latitude),
            "longitude": String(format: "%.2f", coordinate.longitude),
            "current": "us_aqi,european_aqi,pm2_5,pm10,ozone,nitrogen_dioxide",
            "timeformat": "unixtime",
        ])
    }

    func report(at coordinate: Coordinate, key: String?, timeZone: TimeZone, using http: any WeatherHTTP) async throws(WeatherError) -> WeatherReport {
        guard let forecast = Self.forecastRequest(at: coordinate), let air = Self.airRequest(at: coordinate) else { throw .unreadable }
        // Air quality is extra: the forecast stands without it.
        async let airData: Data? = { try? await http.data(for: air) }()
        let forecastData = try await http.data(for: forecast)
        return try Self.report(forecast: forecastData, air: await airData, at: coordinate, timeZone: timeZone, fetched: Date())
    }

    /// Where its quarter-hour rain is real model data: North America and central Europe. Elsewhere it's
    /// hourly data split in four, too coarse to say when rain starts.
    static func hasQuarterHourRain(_ coordinate: Coordinate) -> Bool {
        let northAmerica = (15.0 ... 72.0).contains(coordinate.latitude) && (-170.0 ... -50.0).contains(coordinate.longitude)
        let centralEurope = (41.0 ... 58.0).contains(coordinate.latitude) && (-6.0 ... 22.0).contains(coordinate.longitude)
        return northAmerica || centralEurope
    }

    static func report(forecast: Data, air: Data?, at coordinate: Coordinate, timeZone fallback: TimeZone, fetched: Date) throws(WeatherError) -> WeatherReport {
        let json = try JSON.object(forecast)
        guard let current = json["current"] as? [String: Any], let temperature = JSON.double(current["temperature_2m"]),
              let time = JSON.double(current["time"]) else { throw .unreadable }
        let timeZone = (json["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? fallback

        var report = WeatherReport(provider: .openMeteo, fetched: fetched, timeZone: timeZone, current: .init(
            time: Date(timeIntervalSince1970: time),
            condition: condition(JSON.int(current["weather_code"])),
            isDay: JSON.int(current["is_day"]) != 0,
            temperature: temperature,
            feelsLike: JSON.double(current["apparent_temperature"]),
            humidity: JSON.double(current["relative_humidity_2m"]),
            dewPoint: JSON.double(current["dew_point_2m"]),
            pressure: JSON.double(current["pressure_msl"]),
            windSpeed: JSON.double(current["wind_speed_10m"]),
            windGust: JSON.double(current["wind_gusts_10m"]),
            windDirection: JSON.double(current["wind_direction_10m"]),
            visibility: JSON.double(current["visibility"]).map { $0 / 1000 },
            uvIndex: JSON.double(current["uv_index"]),
            cloudCover: JSON.double(current["cloud_cover"]),
            // The last quarter hour's millimeters, as millimeters an hour.
            precipitation: JSON.double(current["precipitation"]).map { $0 * 4 }
        ))

        if let hourly = json["hourly"] as? [String: Any] {
            let times = JSON.doubles(hourly["time"]), temperatures = JSON.doubles(hourly["temperature_2m"])
            let feels = JSON.doubles(hourly["apparent_temperature"]), codes = JSON.doubles(hourly["weather_code"])
            let chances = JSON.doubles(hourly["precipitation_probability"]), amounts = JSON.doubles(hourly["precipitation"])
            let days = JSON.doubles(hourly["is_day"]), pressures = JSON.doubles(hourly["pressure_msl"])
            let uv = JSON.doubles(hourly["uv_index"]), winds = JSON.doubles(hourly["wind_speed_10m"])
            report.hourly = times.indices.compactMap { index -> WeatherReport.Hour? in
                guard let time = times[index], let temperature = temperatures[safe: index] ?? nil else { return nil }
                return WeatherReport.Hour(
                    time: Date(timeIntervalSince1970: time), condition: condition((codes[safe: index] ?? nil).map { Int($0) }),
                    isDay: (days[safe: index] ?? nil) != 0, temperature: temperature, feelsLike: feels[safe: index] ?? nil,
                    precipitationChance: chances[safe: index] ?? nil, precipitation: amounts[safe: index] ?? nil,
                    pressure: pressures[safe: index] ?? nil, uvIndex: uv[safe: index] ?? nil, windSpeed: winds[safe: index] ?? nil)
            }
        }

        if hasQuarterHourRain(coordinate), let quarters = json["minutely_15"] as? [String: Any] {
            let times = JSON.doubles(quarters["time"]), amounts = JSON.doubles(quarters["precipitation"])
            report.minutely = times.indices.compactMap { index in
                guard let time = times[index], let amount = amounts[safe: index] ?? nil else { return nil }
                // Each is the quarter hour before its time, so it's placed at the quarter's start.
                return WeatherReport.Minute(time: Date(timeIntervalSince1970: time - 900), intensity: amount * 4)
            }
        }

        if let daily = json["daily"] as? [String: Any] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let times = JSON.doubles(daily["time"]), codes = JSON.doubles(daily["weather_code"])
            let highs = JSON.doubles(daily["temperature_2m_max"]), lows = JSON.doubles(daily["temperature_2m_min"])
            let chances = JSON.doubles(daily["precipitation_probability_max"]), amounts = JSON.doubles(daily["precipitation_sum"])
            let sunrises = JSON.doubles(daily["sunrise"]), sunsets = JSON.doubles(daily["sunset"])
            let uv = JSON.doubles(daily["uv_index_max"]), winds = JSON.doubles(daily["wind_speed_10m_max"])
            report.daily = times.indices.compactMap { index -> WeatherReport.Day? in
                guard let time = times[index], let high = highs[safe: index] ?? nil, let low = lows[safe: index] ?? nil else { return nil }
                // Days start at midnight by the offset when asked, even across a daylight saving change, so
                // each is told by its midday instead.
                let day = calendar.startOfDay(for: Date(timeIntervalSince1970: time + 12 * 3600))
                return WeatherReport.Day(
                    date: day, condition: condition((codes[safe: index] ?? nil).map { Int($0) }), high: high, low: low,
                    precipitationChance: chances[safe: index] ?? nil, precipitation: amounts[safe: index] ?? nil,
                    sunrise: (sunrises[safe: index] ?? nil).map(Date.init(timeIntervalSince1970:)),
                    sunset: (sunsets[safe: index] ?? nil).map(Date.init(timeIntervalSince1970:)),
                    uvIndexMax: uv[safe: index] ?? nil, windSpeedMax: winds[safe: index] ?? nil)
            }
        }

        if let air, let airJSON = try? JSON.object(air), let now = airJSON["current"] as? [String: Any] {
            let quality = WeatherReport.AirQuality(
                usIndex: JSON.int(now["us_aqi"]), europeanIndex: JSON.int(now["european_aqi"]), pm25: JSON.double(now["pm2_5"]),
                pm10: JSON.double(now["pm10"]), ozone: JSON.double(now["ozone"]), nitrogenDioxide: JSON.double(now["nitrogen_dioxide"]))
            if quality.usIndex != nil || quality.europeanIndex != nil { report.air = quality }
        }
        return report
    }

    /// The WMO codes Open-Meteo reports.
    static func condition(_ code: Int?) -> WeatherCondition {
        switch code {
        case 0: .clear
        case 1: .mostlyClear
        case 2: .partlyCloudy
        case 3: .cloudy
        case 45, 48: .fog
        case 51, 53, 55: .drizzle
        case 56, 57, 66, 67: .freezingRain
        case 61, 63, 80, 81: .rain
        case 65, 82: .heavyRain
        case 71, 73, 77, 85: .snow
        case 75, 86: .heavySnow
        case 95, 97: .thunderstorm
        case 96, 99: .hail
        default: .cloudy
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

import AppKit
import Foundation
import Testing
@testable import HoverEnhance

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/weather"))
    return try Data(contentsOf: url)
}

private let berlin = Coordinate(latitude: 52.52, longitude: 13.41)

struct OpenMeteoTests {
    @Test func aForecastReadsInFull() throws {
        let report = try OpenMeteo.report(forecast: try fixture("open-meteo-forecast"), air: try fixture("open-meteo-air"), at: berlin,
                                          timeZone: .current, fetched: Date(timeIntervalSince1970: 1_791_804_700))
        #expect(report.provider == .openMeteo)
        #expect(report.timeZone.identifier == "Europe/Berlin")
        #expect(report.current.temperature == 12.6 && report.current.condition == .partlyCloudy && report.current.isDay)
        #expect(report.current.windSpeed != nil && report.current.visibility.map { $0 < 100 } == true, "visibility comes in meters, kept in km")
        #expect(report.hourly.count == 240 && report.daily.count == 10)
        #expect(report.daily[0].high == 13.7 && report.daily[1].high == 15.7)
        #expect(report.daily.allSatisfy { $0.sunrise != nil && $0.sunset != nil })
        // Each day is its local midnight in Berlin.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = report.timeZone
        #expect(report.daily.allSatisfy { calendar.startOfDay(for: $0.date) == $0.date })
        #expect(report.minutely.count == 8 && report.minutely.allSatisfy { $0.intensity == 0 })
        #expect(report.air?.usIndex == 31 && report.air?.europeanIndex == 17)
    }

    @Test func quarterHourRainIsUsedOnlyWhereItsReal() throws {
        let sydney = Coordinate(latitude: -33.87, longitude: 151.21)
        let report = try OpenMeteo.report(forecast: try fixture("open-meteo-forecast"), air: nil, at: sydney, timeZone: .current, fetched: Date())
        #expect(report.minutely.isEmpty && report.air == nil)
        #expect(OpenMeteo.hasQuarterHourRain(Coordinate(latitude: 40.71, longitude: -74.01)))
    }

    @Test func requestsSendOnlyARoundedLocation() throws {
        let url = try #require(OpenMeteo.forecastRequest(at: Coordinate(latitude: 40.712776, longitude: -74.005974))?.url?.absoluteString)
        #expect(url.contains("latitude=40.71") && url.contains("longitude=-74.01") && !url.contains("40.7127"))
    }

    @Test func weatherCodesBecomeConditions() {
        #expect(OpenMeteo.condition(0) == .clear)
        #expect(OpenMeteo.condition(3) == .cloudy)
        #expect(OpenMeteo.condition(48) == .fog)
        #expect(OpenMeteo.condition(65) == .heavyRain)
        #expect(OpenMeteo.condition(97) == .thunderstorm)
        #expect(OpenMeteo.condition(99) == .hail)
        #expect(OpenMeteo.condition(nil) == .cloudy)
    }

    @Test func zeroesAndOnesAreNumbersNotBooleans() {
        #expect(JSON.double(NSNumber(value: 0.0)) == 0 && JSON.double(NSNumber(value: 1)) == 1)
        #expect(JSON.double(kCFBooleanTrue) == nil)
        // Nothing a forecast holds is infinite, and turning one into an Int would trap.
        #expect(JSON.double("nan") == nil && JSON.double("inf") == nil && JSON.double(NSNumber(value: 1e300)) == nil && JSON.int("1e300") == nil)
    }

    @Test func anHoursRainIsTheNextEntrys() throws {
        let forecast = try fixture("open-meteo-forecast")
        let report = try OpenMeteo.report(forecast: forecast, air: nil, at: berlin, timeZone: .current, fetched: Date())
        let hourly = try #require(try JSON.object(forecast)["hourly"] as? [String: Any])
        #expect(report.hourly[0].precipitationChance == JSON.doubles(hourly["precipitation_probability"])[1])
        #expect(report.hourly.last?.precipitationChance == nil)
    }

    @Test func somethingElseIsUnreadable() {
        #expect(throws: WeatherError.unreadable) {
            try OpenMeteo.report(forecast: Data(#"{"error":true,"reason":"Invalid value"}"#.utf8), air: nil, at: berlin, timeZone: .current, fetched: Date())
        }
    }
}

struct OpenWeatherMapTests {
    @Test func theDocumentedExampleReadsInFull() throws {
        let rome = try #require(TimeZone(identifier: "Europe/Rome"))
        let report = try OpenWeatherMap.report(current: try fixture("owm-weather"), forecast: try fixture("owm-forecast"), air: try fixture("owm-air"),
                                               timeZone: rome, fetched: Date())
        #expect(report.provider == .openWeatherMap && report.timeZone == rome)
        #expect(report.current.temperature == 25.33 && report.current.condition == .rain && report.current.isDay)
        #expect(report.current.visibility == 10 && report.current.pressure == 1015 && report.current.precipitation == 3.16)
        // Not given by the free API: worked out from temperature and humidity.
        #expect(report.current.dewPoint.map { (18 ... 19).contains($0) } == true)
        #expect(report.hourly.count == 4 && report.hourly[0].precipitationChance == 32)
        #expect(!report.daily.isEmpty && report.daily[0].sunrise != nil)
        // OpenWeatherMap's own index is 1 to 5; the US one comes from the particle amounts.
        #expect(report.air?.usIndex == 77 && report.air?.pm25 == 23.253)
    }

    @Test func conditionCodesBecomeConditions() {
        #expect(OpenWeatherMap.condition(211) == .thunderstorm)
        #expect(OpenWeatherMap.condition(502) == .heavyRain)
        #expect(OpenWeatherMap.condition(511) == .freezingRain)
        #expect(OpenWeatherMap.condition(613) == .sleet)
        #expect(OpenWeatherMap.condition(741) == .fog)
        #expect(OpenWeatherMap.condition(800) == .clear && OpenWeatherMap.condition(804) == .cloudy)
    }

    @Test func theKeyGoesOnlyInTheQuery() throws {
        let url = try #require(OpenWeatherMap.request("weather", at: Coordinate(latitude: 40.712776, longitude: -74.005974), key: "abc123")?.url)
        #expect(url.host() == "api.openweathermap.org" && url.query()?.contains("appid=abc123") == true && url.query()?.contains("lat=40.71") == true)
    }
}

struct WeatherAPIcomTests {
    @Test func aForecastReadsInFull() throws {
        let fetched = Date(timeIntervalSince1970: 1_774_203_300)
        let report = try WeatherAPIcom.report(from: try fixture("weatherapi-forecast"), timeZone: .current, fetched: fetched)
        #expect(report.timeZone.identifier == "Europe/London")
        #expect(report.current.temperature == 12.3 && report.current.condition == .partlyCloudy)
        #expect(report.hourly.count == 72 && report.daily.count == 3)
        // Sunrise is written as local 12-hour time.
        let sunrise = try #require(report.daily[0].sunrise)
        #expect(WeatherTimes(timeZone: report.timeZone).time(sunrise).replacingOccurrences(of: "\u{202F}", with: " ") == "6:03 AM")
        #expect(report.alerts.map(\.title) == ["Wind Advisory"])
        // The US category (1 to 6) isn't the index; the index comes from PM2.5.
        #expect(report.air?.usIndex == 46)
        // Wind comes in km/h and is kept in m/s.
        #expect(report.current.windSpeed.map { $0 < 30 } == true)
    }

    @Test func conditionCodesBecomeConditions() {
        #expect(WeatherAPIcom.condition(1000) == .clear && WeatherAPIcom.condition(1195) == .heavyRain)
        #expect(WeatherAPIcom.condition(1201) == .freezingRain && WeatherAPIcom.condition(1225) == .heavySnow)
        #expect(WeatherAPIcom.condition(1276) == .thunderstorm && WeatherAPIcom.condition(1135) == .fog)
    }
}

struct TomorrowIOTests {
    @Test func theDocumentedExampleReadsInFull() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let report = try TomorrowIO.report(forecast: try fixture("tomorrow-forecast"), realtime: try fixture("tomorrow-realtime"), timeZone: newYork, fetched: Date())
        #expect(report.minutely.count == 60 && report.hourly.count == 120 && report.daily.count == 7)
        #expect(report.current.temperature == 1.88 && report.current.condition == .cloudy)
        // Days start at 6 am local, and are told by their date there.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        #expect(calendar.dateComponents([.month, .day, .hour], from: report.daily[0].date) == DateComponents(month: 2, day: 8, hour: 0))
        #expect(report.daily[0].condition == .snow && report.daily[0].high == -1.7)
        #expect(report.daily.allSatisfy { $0.sunrise != nil })
    }

    @Test func withoutRealtimeTheHourStandsIn() throws {
        let report = try TomorrowIO.report(forecast: try fixture("tomorrow-forecast"), realtime: nil, timeZone: .current, fetched: Date())
        #expect(report.current.pressure != nil)
    }

    @Test func weatherCodesBecomeConditions() {
        #expect(TomorrowIO.condition(1100) == .mostlyClear && TomorrowIO.condition(4201) == .heavyRain)
        #expect(TomorrowIO.condition(6201) == .freezingRain && TomorrowIO.condition(7101) == .sleet)
        #expect(TomorrowIO.condition(80001) == .thunderstorm && TomorrowIO.condition(21070) == .fog)
    }
}

struct PirateWeatherTests {
    @Test func aForecastReadsInFull() throws {
        let fetched = Date(timeIntervalSince1970: 1_762_718_100)
        let report = try PirateWeather.report(from: try fixture("pirateweather-forecast"), timeZone: .current, fetched: fetched)
        #expect(report.timeZone.identifier == "America/Toronto")
        #expect(report.current.temperature == -0.88 && report.current.condition == .snow)
        // Fractions become percents.
        #expect(report.current.humidity == 82)
        #expect(report.minutely.count == 61 && report.hourly.count == 48 && report.daily.count == 8)
        #expect(report.alerts.count == 1 && report.alerts[0].url != nil)
        // In SI units the index is Europe's.
        #expect(report.air?.europeanIndex == 18)
        #expect(report.hourly.contains { $0.condition == .freezingRain })
    }

    @Test func alertLinksAreWebPagesOnly() throws {
        let fetched = Date(timeIntervalSince1970: 1_762_718_100)
        let page = try fixture("pirateweather-forecast")
        let original = "https://severeweather.wmo.int/v2/cap-alerts/ca-msc-xx/2025/11/09/16/09/12-3372a8228b861e43112cdf50691d180.xml"
        for link in ["file:///Applications/Calculator.app", "smb://server/share"] {
            let changed = Data(String(decoding: page, as: UTF8.self).replacingOccurrences(of: original, with: link).utf8)
            let report = try PirateWeather.report(from: changed, timeZone: .current, fetched: fetched)
            #expect(report.alerts.count == 1 && report.alerts[0].url == nil, "\(link)")
        }
    }

    @Test func iconsBecomeConditions() {
        #expect(PirateWeather.condition(["icon": "rain", "precipIntensity": 9.0]) == .heavyRain)
        #expect(PirateWeather.condition(["icon": "sleet", "precipType": "ice"]) == .freezingRain)
        #expect(PirateWeather.condition(["icon": "partly-cloudy-night"]) == .partlyCloudy)
        #expect(PirateWeather.condition(["icon": "wind"]) == .windy)
    }

    @Test func theKeyIsAPathSegment() throws {
        let url = try #require(PirateWeather.request(at: Coordinate(latitude: 43.65, longitude: -79.38), key: "abc")?.url?.absoluteString)
        #expect(url.hasPrefix("https://api.pirateweather.net/forecast/abc/43.65,-79.38?") && url.contains("units=si") && url.contains("version=2"))
    }
}

struct AccuWeatherTests {
    /// 2 PM in New York on the fixtures' day.
    private let fetched = Date(timeIntervalSince1970: 1_791_828_000)

    private func report() throws -> WeatherReport {
        let location = try AccuWeather.location(from: try fixture("accuweather-location"))
        return try AccuWeather.report(current: try fixture("accuweather-current"), hourly: try fixture("accuweather-hourly"),
                                      daily: try fixture("accuweather-daily"), timeZone: try #require(location.timeZone), fetched: fetched)
    }

    @Test func aPlaceIsFoundByItsKey() throws {
        let location = try AccuWeather.location(from: try fixture("accuweather-location"))
        #expect(location == .init(key: "349727", timeZone: TimeZone(identifier: "America/New_York")))
        #expect(throws: WeatherError.unreadable) { try AccuWeather.location(from: Data("[]".utf8)) }
    }

    @Test func aForecastReadsInFull() throws {
        let report = try report()
        #expect(report.provider == .accuWeather && report.timeZone.identifier == "America/New_York")
        let now = report.current
        #expect(now.temperature == 16.1 && now.condition == .partlyCloudy && now.isDay)
        #expect(now.feelsLike == 15 && now.feelsLikeInShade == 14.2 && now.humidity == 58 && now.dewPoint == 7.8)
        // Wind comes in km/h and is kept in m/s.
        #expect(now.windSpeed.map { abs($0 - 14.8 / 3.6) < 0.001 } == true && now.windDirection == 250)
        #expect(now.pressure == 1016.6 && now.uvIndex == 2.3 && now.visibility == 16.1 && now.cloudCover == 45)
        #expect(now.changeSinceYesterday == -3.3 && now.precipitationLast24Hours == 4.1)
        // Its own word for which way pressure is going wins over the hours, which don't give pressure.
        #expect(report.pressureTrend(from: fetched) == .falling)
        // Given as plain HTTP.
        #expect(report.link?.absoluteString.hasPrefix("https://www.accuweather.com/") == true)

        #expect(report.hourly.count == 12 && report.hourly.allSatisfy { $0.feelsLike != nil && $0.precipitationChance != nil })
        #expect(report.hourly.contains { $0.condition == .heavyRain } && report.hourly.contains { $0.condition == .thunderstorm })
        #expect(report.hourly.contains { !$0.isDay })

        #expect(report.daily.count == 5)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = report.timeZone
        #expect(report.daily.allSatisfy { calendar.startOfDay(for: $0.date) == $0.date })
        let today = report.daily[0]
        #expect(today.high == 18.3 && today.low == 10.6 && today.condition == .partlyCloudy)
        // The day's chance is the higher of day and night's, and its rain both together.
        #expect(today.precipitationChance == 85 && today.precipitation == 14.2 && today.uvIndexMax == 3)
        #expect(today.sunrise.map { WeatherTimes(timeZone: report.timeZone).time($0).replacingOccurrences(of: "\u{202F}", with: " ") } == "7:06 AM")
        #expect(report.daily[1].condition == .thunderstorm)
        #expect(report.summary == "Heavy rain tonight; a thunderstorm in spots Tuesday afternoon")
    }

    @Test func todaysAirAndPollenAreRated() throws {
        let report = try report()
        // The rating, not a number: what its value measures isn't documented.
        #expect(report.air == .init(rating: .init(name: "Good", level: 0), mainPollutant: "Ozone"))
        #expect(report.pollen.map(\.kind) == [.tree, .grass, .ragweed, .mold])
        #expect(report.pollen[0].rating == .init(name: "Very high", level: 3))
        #expect(report.pollen[3].rating == .init(name: "Moderate", level: 1))
    }

    @Test func theKeyGoesInAHeaderNotTheURL() throws {
        let lookup = try #require(AccuWeather.locationRequest(at: Coordinate(latitude: 40.712776, longitude: -74.005974), key: "abc123"))
        #expect(lookup.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(lookup.url?.absoluteString == "https://dataservice.accuweather.com/locations/v1/cities/geoposition/search?q=40.71,-74.01")
        let daily = try #require(AccuWeather.request("forecasts/v1/daily/5day", for: "349727", key: "abc123")?.url?.absoluteString)
        #expect(daily == "https://dataservice.accuweather.com/forecasts/v1/daily/5day/349727?details=true&metric=true")
        // Nothing pasted with a key can add a header.
        #expect(AccuWeather.locationRequest(at: berlin, key: "abc\r\nX-Other: 1") == nil)
    }

    @Test func aKeyThatCouldntBeSentIsTurnedDown() async {
        let http = FixtureHTTP()
        await #expect(throws: WeatherError.badKey) {
            try await AccuWeather(locations: AccuWeatherLocations()).report(at: berlin, key: "two words", timeZone: .current, using: http)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func aPlaceIsLookedUpOnce() async throws {
        let http = FixtureHTTP()
        let source = AccuWeather(locations: AccuWeatherLocations())
        let newYork = Coordinate(latitude: 40.71, longitude: -74.01)
        let first = try await source.report(at: newYork, key: "abc", timeZone: .current, using: http)
        _ = try await source.report(at: Coordinate(latitude: 40.712, longitude: -74.006), key: "abc", timeZone: .current, using: http)
        #expect(first.timeZone.identifier == "America/New_York")
        // One lookup, then three forecasts each time.
        #expect(http.requests.filter { $0.path().hasPrefix("/locations/") }.count == 1 && http.requests.count == 7)
    }

    @Test func iconsBecomeConditions() {
        #expect(AccuWeather.condition(1) == .clear && AccuWeather.condition(34) == .mostlyClear && AccuWeather.condition(36) == .partlyCloudy)
        #expect(AccuWeather.condition(8) == .cloudy && AccuWeather.condition(11) == .fog && AccuWeather.condition(37) == .haze)
        #expect(AccuWeather.condition(18) == .rain && AccuWeather.condition(18, intensity: "Heavy") == .heavyRain)
        #expect(AccuWeather.condition(42) == .thunderstorm && AccuWeather.condition(22, intensity: "Heavy") == .heavySnow)
        #expect(AccuWeather.condition(26) == .freezingRain && AccuWeather.condition(29) == .sleet && AccuWeather.condition(32) == .windy)
        #expect(AccuWeather.condition(nil) == .cloudy)
    }
}

struct QuotaTests {
    @Test func aUsedUpQuotaIsntABadKey() {
        #expect(URLSessionWeatherHTTP.saysQuota(Data(#"{"error":{"code":2007,"message":"API key has exceeded calls per month quota."}}"#.utf8)))
        #expect(!URLSessionWeatherHTTP.saysQuota(Data(#"{"error":{"code":2006,"message":"API key is invalid."}}"#.utf8)))
    }
}

struct AirQualityIndexTests {
    @Test func theUSIndexFollowsTheEPABreakpoints() {
        #expect(WeatherReport.AirQuality.usIndex(pm25: 9, pm10: nil) == 50)
        #expect(WeatherReport.AirQuality.usIndex(pm25: 35.4, pm10: nil) == 100)
        #expect(WeatherReport.AirQuality.usIndex(pm25: 3, pm10: 160) == 103)
        #expect(WeatherReport.AirQuality.usIndex(pm25: nil, pm10: nil) == nil)
    }
}

struct NWSAlertsTests {
    @Test func activeAlertsComeOnceEachMostSevereFirst() throws {
        // At 10 AM in Arizona, the 5 AM alerts have ended.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-12T10:00:00-07:00"))
        let alerts = try NWSAlerts.alerts(from: try fixture("nws-alerts"), at: Coordinate(latitude: 35.2, longitude: -111.65), now: now)
        #expect(alerts.map(\.title) == ["Flash Flood Warning", "Flood Watch"])
        #expect(alerts.allSatisfy { $0.severity == .severe && $0.source?.hasPrefix("NWS") == true && $0.url != nil })
    }

    @Test func onlyUSPlacesAreAsked() throws {
        func place(_ country: String?) -> WeatherPlace {
            WeatherPlace(name: "Somewhere", coordinate: Coordinate(latitude: 43.65, longitude: -79.38), countryCode: country)
        }
        #expect(NWSAlerts.covers(place("US")) && NWSAlerts.covers(place("pr")))
        // Toronto is inside any box drawn around the lower 48; it's the country that decides.
        #expect(!NWSAlerts.covers(place("CA")) && !NWSAlerts.covers(place("MX")))
        // Unknown means not sent.
        #expect(!NWSAlerts.covers(place(nil)))
        let request = try #require(NWSAlerts.request(at: Coordinate(latitude: 40.712776, longitude: -74.005974)))
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("HoverEnhance") == true)
        #expect(request.url?.absoluteString.contains("point=40.71,-74.01") == true)
    }
}

struct WeatherModelTests {
    @Test func moonPhasesFollowTheCalendar() throws {
        let full = MoonPhase(at: try #require(ISO8601DateFormatter().date(from: "2024-01-25T17:54:00Z")))
        #expect(full.name == "Full moon" && full.illumination > 0.99)
        let new = MoonPhase(at: try #require(ISO8601DateFormatter().date(from: "2024-01-11T11:57:00Z")))
        #expect(new.name == "New moon" && new.illumination < 0.01)
        #expect(MoonPhase(at: try #require(ISO8601DateFormatter().date(from: "2024-01-18T03:53:00Z"))).name == "First quarter")
    }

    @Test func theNextHourSaysWhenRainStartsOrStops() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func report(_ intensities: [Double]) -> WeatherReport {
            var report = WeatherReport(provider: .openMeteo, fetched: now, timeZone: .current,
                                       current: .init(time: now, condition: .cloudy, temperature: 10))
            report.minutely = intensities.enumerated().map { .init(time: now.addingTimeInterval(Double($0.offset) * 900), intensity: $0.element) }
            return report
        }
        #expect(report([0, 0, 0, 0]).nextHourPrecipitation(from: now) == .dry)
        #expect(report([0, 0, 1.2, 2]).nextHourPrecipitation(from: now) == .starting(now.addingTimeInterval(1800)))
        #expect(report([2, 1, 0, 0]).nextHourPrecipitation(from: now) == .now(until: now.addingTimeInterval(1800)))
        #expect(report([2, 2, 2, 2]).nextHourPrecipitation(from: now) == .now(until: nil))
        // Partway through the quarter hour under way, its rain is falling now, not starting next quarter.
        #expect(report([2, 2, 2, 2, 2]).nextHourPrecipitation(from: now.addingTimeInterval(100)) == .now(until: nil))
        #expect(report([0, 2, 2, 2, 2]).nextHourPrecipitation(from: now.addingTimeInterval(100)) == .starting(now.addingTimeInterval(900)))

        var hourlyOnly = report([])
        hourlyOnly.hourly = [.init(time: now, condition: .rain, temperature: 10, precipitationChance: 70)]
        #expect(hourlyOnly.nextHourPrecipitation(from: now) == .chance(70))
    }

    @Test func theNextDayIsTwentyFourHoursOfSteps() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func report(step: TimeInterval, count: Int) -> WeatherReport {
            var report = WeatherReport(provider: .openMeteo, fetched: now, timeZone: .current, current: .init(time: now, condition: .clear, temperature: 10))
            report.hourly = (0..<count).map { .init(time: now.addingTimeInterval(Double($0) * step - step / 2), condition: .clear, temperature: 10) }
            return report
        }
        #expect(report(step: 3600, count: 48).nextDay(from: now).count == 25)
        #expect(report(step: 3 * 3600, count: 40).nextDay(from: now).count == 9)
    }

    @Test func whatsFallingIsNamed() {
        #expect(WeatherCondition.heavySnow.precipitationWord == "Snow" && WeatherCondition.thunderstorm.precipitationWord == "Rain")
        #expect(WeatherCondition.freezingRain.precipitationWord == "Freezing rain")
    }

    @Test func pressureTrendsComeFromTheHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var report = WeatherReport(provider: .openMeteo, fetched: now, timeZone: .current, current: .init(time: now, condition: .clear, temperature: 10))
        report.hourly = (0..<4).map { .init(time: now.addingTimeInterval(Double($0) * 3600), condition: .clear, temperature: 10, pressure: 1010 + Double($0)) }
        #expect(report.pressureTrend(from: now) == .rising)
    }

    @Test func onlyAppleWeatherInTheMenuBarTriggersIt() {
        var info = HoverInfo(pid: 1, bundleID: WeatherTrigger.bundleID)
        info.subrole = "AXMenuExtra"
        #expect(WeatherTrigger.matches(info))
        info.frame = CGRect(x: 1258, y: 3, width: 66, height: 24)
        #expect(MediaResolver.source(for: info) == .weather(item: CGRect(x: 1258, y: 3, width: 66, height: 24)))
        info.subrole = "AXWindow"
        #expect(!WeatherTrigger.matches(info))
        #expect(OtherAppsPolicy().allows(.weather(item: .zero), in: .other, keyHeld: false))
    }
}

struct WeatherUnitsTests {
    private let us = WeatherUnits.forLocale(Locale(identifier: "en_US"))
    private let metric = WeatherUnits.forLocale(Locale(identifier: "de_DE"))

    @Test func unitsFollowTheRegion() {
        #expect(us == WeatherUnits(temperature: .fahrenheit, speed: .mph, pressure: .inHg, precipitation: .inches, distance: .miles))
        #expect(metric.temperature == .celsius && metric.speed == .kmh && metric.distance == .kilometers)
        #expect(WeatherUnits.forLocale(Locale(identifier: "en_GB")).speed == .mph)
    }

    @Test func valuesAreWrittenInThem() {
        #expect(us.degrees(0) == "32°" && us.degrees(16.1) == "61°" && metric.degrees(-0.4) == "0°")
        #expect(us.wind(10) == "22 mph" && metric.wind(10) == "36 km/h")
        #expect(us.pressure(1013.25) == "29.92 inHg" && metric.pressure(1013.25) == "1013 hPa")
        #expect(us.precipitation(25.4) == "1.00 in" && metric.precipitation(2.34) == "2.3 mm")
        #expect(us.distance(16.09) == "10 mi" && metric.distance(4.25) == "4.2 km")
        #expect(us.change(-3.3) == "6° cooler" && metric.change(2.6) == "3° warmer" && metric.change(0.2) == "No change")
        #expect(WeatherWords.compass(315) == "NW" && WeatherWords.compass(359) == "N" && WeatherWords.compass(-90) == "W")
        #expect(WeatherWords.uvLevel(1) == "Low" && WeatherWords.uvLevel(7) == "High")
        #expect(WeatherWords.airQuality(us: 32).name == "Good" && WeatherWords.airQuality(us: 151).name == "Unhealthy")
    }
}

/// Answers weather requests from fixtures by host, counting them.
private final class FixtureHTTP: WeatherHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URL] = []
    var failNWS = false

    func data(for request: URLRequest) async throws(WeatherError) -> Data {
        guard let url = request.url else { throw .unreadable }
        lock.withLock { requests.append(url) }
        do {
            switch url.host() {
            case "api.open-meteo.com": return try fixture("open-meteo-forecast")
            case "air-quality-api.open-meteo.com": return try fixture("open-meteo-air")
            case "api.weather.gov": if failNWS { throw WeatherError.unavailable(400) } else { return Data(#"{"features":[]}"#.utf8) }
            case "api.weatherapi.com": return try fixture("weatherapi-forecast")
            case "dataservice.accuweather.com":
                let path = url.path()
                return try fixture(path.hasPrefix("/locations/") ? "accuweather-location" : path.hasPrefix("/currentconditions/") ? "accuweather-current"
                                   : path.contains("/hourly/") ? "accuweather-hourly" : "accuweather-daily")
            default: throw WeatherError.unavailable(404)
            }
        } catch let error as WeatherError {
            throw error
        } catch {
            throw .unreadable
        }
    }
}

@MainActor
struct WeatherServiceTests {
    private let newYork = WeatherPlace(name: "New York", coordinate: Coordinate(latitude: 40.71, longitude: -74.01), timeZoneID: "America/New_York",
                                       countryCode: "US")

    @Test func aForecastIsKeptTenMinutesAndSharedByTheSamePlace() async throws {
        let http = FixtureHTTP()
        let service = WeatherService(http: http, currentLocation: { () async throws(WeatherError) in throw .noLocation }, key: { _ in nil })
        guard case .success(let first) = await service.report(.openMeteo, at: newYork, alertsFromNWS: true) else { Issue.record("no report"); return }
        #expect(first.current.temperature == 12.6)
        _ = await service.report(.openMeteo, at: newYork, alertsFromNWS: true)
        // One forecast, one air quality, one NWS lookup: the second report came from what was kept.
        #expect(http.requests.count == 3)
        #expect(http.requests.contains { $0.host() == "api.weather.gov" })
        #expect(service.kept(.openMeteo, at: newYork) != nil)
    }

    @Test func alertsFailingDoesntLoseTheForecast() async {
        let http = FixtureHTTP()
        http.failNWS = true
        let service = WeatherService(http: http, currentLocation: { () async throws(WeatherError) in throw .noLocation }, key: { _ in nil })
        guard case .success(let report) = await service.report(.openMeteo, at: newYork, alertsFromNWS: true) else { Issue.record("no report"); return }
        #expect(report.alerts.isEmpty)
    }

    @Test func providersWithAlertsOfTheirOwnDontAskTheNWS() async {
        let http = FixtureHTTP()
        let service = WeatherService(http: http, currentLocation: { () async throws(WeatherError) in throw .noLocation }, key: { _ in "key" })
        _ = await service.report(.weatherAPI, at: newYork, alertsFromNWS: true)
        #expect(http.requests.count == 1 && !http.requests.contains { $0.host() == "api.weather.gov" })
    }

    @Test func hiddenAlertsArentLookedUp() async {
        let http = FixtureHTTP()
        let service = WeatherService(http: http, currentLocation: { () async throws(WeatherError) in throw .noLocation }, key: { _ in nil })
        let name = "HoverEnhanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.weatherLocation = .place(newYork)
        settings.weatherHiddenSections = [.alerts]
        let model = WeatherPopupModel(settings: settings, service: service)
        await model.load()
        guard case .report = model.state else { Issue.record("no report"); return }
        #expect(!http.requests.contains { $0.host() == "api.weather.gov" })
    }

    @Test func outsideTheUSTheNWSIsntAsked() async {
        let http = FixtureHTTP()
        let service = WeatherService(http: http, currentLocation: { () async throws(WeatherError) in throw .noLocation }, key: { _ in nil })
        _ = await service.report(.openMeteo, at: WeatherPlace(name: "Berlin", coordinate: berlin, countryCode: "DE"), alertsFromNWS: true)
        #expect(!http.requests.contains { $0.host() == "api.weather.gov" })
    }

    @Test func keyedProvidersWithoutAKeyAskForOne() async {
        let http = FixtureHTTP()
        let service = WeatherService(http: http, currentLocation: { () async throws(WeatherError) in throw .noLocation }, key: { _ in nil })
        for provider in WeatherProviderID.allCases where provider.needsKey {
            guard case .failure(.needsKey) = await service.report(provider, at: newYork, alertsFromNWS: false) else {
                Issue.record("\(provider) didn't ask for a key"); continue
            }
        }
        #expect(http.requests.isEmpty)
    }

    @Test func noLocationMeansNothingIsLookedUp() async {
        let http = FixtureHTTP()
        let service = WeatherService(http: http, currentLocation: { () async throws(WeatherError) in throw .noLocation }, key: { _ in nil })
        await #expect(throws: WeatherError.noLocation) { try await service.place(for: nil) }
        #expect(http.requests.isEmpty)
    }
}

@MainActor
struct WeatherSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "HoverEnhanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func weatherStartsOnWithNoLocationAndOpenMeteo() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.weatherEnabled && settings.weatherProvider == .openMeteo && settings.weatherLocation == nil)
        #expect(settings.weatherUnits == .forLocale() && settings.weatherHiddenSections.isEmpty && settings.weatherUsesNWSAlerts)
        #expect(settings.filter.allows(.weather(item: .zero)))
        settings.weatherEnabled = false
        #expect(!settings.filter.allows(.weather(item: .zero)))
    }

    @Test func weatherChoicesPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        let place = WeatherPlace(name: "Lisbon", coordinate: Coordinate(latitude: 38.72, longitude: -9.14), timeZoneID: "Europe/Lisbon")
        settings.weatherLocation = .place(place)
        settings.weatherProvider = .pirateWeather
        settings.weatherUnits.speed = .knots
        settings.weatherHiddenSections = [.airQuality]
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.weatherLocation == .place(place) && reloaded.weatherProvider == .pirateWeather)
        #expect(reloaded.weatherUnits.speed == .knots && reloaded.weatherHiddenSections == [.airQuality])
        reloaded.weatherLocation = .current
        #expect(AppSettings(defaults: defaults).weatherLocation == .current)
    }
}

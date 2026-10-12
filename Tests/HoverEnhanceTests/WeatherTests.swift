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
    }

    @Test func somethingElseIsUnreadable() {
        #expect(throws: WeatherError.unreadable) {
            try OpenMeteo.report(forecast: Data(#"{"error":true,"reason":"Invalid value"}"#.utf8), air: nil, at: berlin, timeZone: .current, fetched: Date())
        }
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
        #expect(NWSAlerts.covers(Coordinate(latitude: 40.71, longitude: -74.01)))
        #expect(NWSAlerts.covers(Coordinate(latitude: 21.31, longitude: -157.86)))
        #expect(!NWSAlerts.covers(berlin))
        #expect(!NWSAlerts.covers(Coordinate(latitude: 43.65, longitude: -79.38 + 30)))
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

        var hourlyOnly = report([])
        hourlyOnly.hourly = [.init(time: now, condition: .rain, temperature: 10, precipitationChance: 70)]
        #expect(hourlyOnly.nextHourPrecipitation(from: now) == .chance(70))
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
    private let newYork = WeatherPlace(name: "New York", coordinate: Coordinate(latitude: 40.71, longitude: -74.01), timeZoneID: "America/New_York")

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

    @Test func outsideTheUSTheNWSIsntAsked() async {
        let http = FixtureHTTP()
        let service = WeatherService(http: http, currentLocation: { () async throws(WeatherError) in throw .noLocation }, key: { _ in nil })
        _ = await service.report(.openMeteo, at: WeatherPlace(name: "Berlin", coordinate: berlin), alertsFromNWS: true)
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

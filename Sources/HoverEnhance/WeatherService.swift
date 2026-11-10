import Foundation
import Observation

/// Gets forecasts for the popup from the provider and place set in Settings. A forecast is kept ten
/// minutes; an older one, up to a few hours old, is shown at once while a new one loads.
@MainActor
final class WeatherService {
    static let shared = WeatherService()

    static let freshFor: TimeInterval = 10 * 60
    static let keptFor: TimeInterval = 3 * 60 * 60

    private let http: any WeatherHTTP
    private let currentLocation: () async throws(WeatherError) -> WeatherPlace
    private let savedKey: (WeatherProviderID) -> String?
    private var reports: [Key: WeatherReport] = [:]
    private var loading: [Key: Task<Result<WeatherReport, WeatherError>, Never>] = [:]

    private struct Key: Hashable {
        let provider: WeatherProviderID
        let coordinate: Coordinate
    }

    init(http: any WeatherHTTP = URLSessionWeatherHTTP.shared,
         currentLocation: @escaping () async throws(WeatherError) -> WeatherPlace = { () async throws(WeatherError) in try await CurrentLocation.shared.place() },
         key: @escaping (WeatherProviderID) -> String? = { Keychain.string(for: $0.keychainAccount) }) {
        self.http = http
        self.currentLocation = currentLocation
        savedKey = key
    }

    /// The place a choice means: itself, or wherever the Mac is.
    func place(for choice: WeatherLocationChoice?) async throws(WeatherError) -> WeatherPlace {
        switch choice {
        case nil: throw .noLocation
        case .place(let place)?: return place
        case .current?: return try await currentLocation()
        }
    }

    /// A forecast already here for the place, however old, if it's young enough to show.
    func kept(_ provider: WeatherProviderID, at place: WeatherPlace) -> WeatherReport? {
        reports[Key(provider: provider, coordinate: place.coordinate.rounded)].flatMap {
            Date().timeIntervalSince($0.fetched) < Self.keptFor ? $0 : nil
        }
    }

    /// A forecast from the provider, unless one fetched in the last ten minutes is here. Lookups for the
    /// same place share one request.
    func report(_ provider: WeatherProviderID, at place: WeatherPlace, alertsFromNWS: Bool, now: Date = Date()) async -> Result<WeatherReport, WeatherError> {
        let key = Key(provider: provider, coordinate: place.coordinate.rounded)
        if let report = reports[key], now.timeIntervalSince(report.fetched) < Self.freshFor { return .success(report) }
        if let task = loading[key] { return await task.value }
        let apiKey = savedKey(provider)
        let http = http
        let asksNWS = alertsFromNWS && !provider.hasAlerts && NWSAlerts.covers(place)
        let lastAlerts = reports[key]?.alerts ?? []
        let task = Task { () -> Result<WeatherReport, WeatherError> in
            if provider.needsKey, apiKey?.isEmpty != false { return .failure(.needsKey) }
            // Alongside the forecast, so a slow answer doesn't hold it up.
            async let alerts = asksNWS ? try? await NWSAlerts.alerts(at: place.coordinate, using: http) : nil
            do throws(WeatherError) {
                var report = try await provider.source.report(at: place.coordinate, key: apiKey, timeZone: place.timeZone, using: http)
                // Alerts are extra: the forecast stands without them. A lookup that failed says nothing
                // about the alerts found last time, which stay until they end.
                if asksNWS { report.alerts = await alerts ?? lastAlerts }
                return .success(report)
            } catch {
                return .failure(error)
            }
        }
        loading[key] = task
        let result = await task.value
        loading[key] = nil
        if case .success(let report) = result { reports[key] = report }
        return result
    }
}

/// What the popup shows, kept up to date while it's open.
@MainActor @Observable
final class WeatherPopupModel {
    enum State: Equatable {
        case loading
        case report(WeatherReport, place: WeatherPlace)
        case problem(WeatherError)
    }

    private(set) var state: State = .loading
    /// A newer forecast is loading behind the one shown.
    private(set) var isRefreshing = false
    /// The newer forecast didn't come, so the one shown is the old one.
    private(set) var refreshFailed = false
    /// Whether the place is wherever the Mac is, rather than one picked.
    var isCurrentLocation: Bool { location == .current }
    let provider: WeatherProviderID
    let units: WeatherUnits
    let hidden: Set<WeatherSection>
    @ObservationIgnored private let service: WeatherService
    @ObservationIgnored private var location: WeatherLocationChoice?
    @ObservationIgnored private let alertsFromNWS: Bool

    init(settings: AppSettings, service: WeatherService = .shared) {
        provider = settings.weatherProvider
        units = settings.weatherUnits
        hidden = settings.weatherHiddenSections
        location = settings.weatherLocation
        // Not when alerts are hidden: there'd be nothing to show for sending the location.
        alertsFromNWS = settings.weatherUsesNWSAlerts && !settings.weatherHiddenSections.contains(.alerts)
        self.service = service
    }

    /// Already showing `state`, for tests and for checking the popup's look.
    init(showing state: State, provider: WeatherProviderID, units: WeatherUnits, hidden: Set<WeatherSection> = [], service: WeatherService = .shared) {
        self.state = state
        self.provider = provider
        self.units = units
        self.hidden = hidden
        location = nil
        alertsFromNWS = false
        self.service = service
    }

    /// Starts over with another location, as when the popup's Use Current Location is clicked.
    func use(_ choice: WeatherLocationChoice) async {
        location = choice
        await retry()
    }

    func retry() async {
        state = .loading
        await load()
    }

    /// Returns once there's something to show: a kept forecast at once (a newer one keeps loading behind
    /// it), or else a new forecast or what went wrong.
    func load() async {
        let place: WeatherPlace
        do throws(WeatherError) {
            place = try await service.place(for: location)
        } catch {
            state = .problem(error)
            return
        }
        refreshFailed = false
        if let kept = service.kept(provider, at: place) {
            state = .report(kept, place: place)
            if Date().timeIntervalSince(kept.fetched) >= WeatherService.freshFor {
                isRefreshing = true
                Task {
                    switch await service.report(provider, at: place, alertsFromNWS: alertsFromNWS) {
                    case .success(let report): state = .report(report, place: place)
                    case .failure: refreshFailed = true
                    }
                    isRefreshing = false
                }
            }
            return
        }
        switch await service.report(provider, at: place, alertsFromNWS: alertsFromNWS) {
        case .success(let report): state = .report(report, place: place)
        case .failure(let error): state = .problem(error)
        }
    }
}

import CoreLocation
import Foundation
import MapKit

/// A named place, with the time zone its hours are told in.
struct WeatherPlace: Codable, Equatable, Hashable, Sendable {
    var name: String
    var coordinate: Coordinate
    var timeZoneID: String?
    /// "US", from Apple's maps, for knowing whose weather service covers it.
    var countryCode: String?

    var timeZone: TimeZone { timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }
}

/// Where the weather is for: wherever the Mac is, or a place picked in Settings.
enum WeatherLocationChoice: Codable, Equatable, Sendable {
    case current
    case place(WeatherPlace)
}

/// Finds where the Mac is, through Location Services, once per half hour at most.
@MainActor
final class CurrentLocation: NSObject, CLLocationManagerDelegate {
    static let shared = CurrentLocation()

    private let manager = CLLocationManager()
    private var found: (place: WeatherPlace, time: Date)?
    private var waiting: [CheckedContinuation<Result<CLLocation, WeatherError>, Never>] = []
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    /// Counts requests for a fix, so a timeout only gives up on its own.
    private var request = 0
    private static let lifetime: TimeInterval = 30 * 60
    /// How long to wait for an answer to the permission prompt, and for a fix, before giving up.
    private static let permissionWait: Duration = .seconds(60)
    private static let fixWait: Duration = .seconds(15)

    override init() {
        super.init()
        manager.delegate = self
        // A forecast covers kilometers; finer would only cost power and privacy.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }

    /// Asks for permission if it hasn't been asked, and says whether it was given. A prompt left
    /// unanswered counts as not yet.
    func requestPermission() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
                Task { [weak self] in
                    try? await Task.sleep(for: Self.permissionWait)
                    self?.resumeAuthorizationWaiters()
                }
            }
        }
        return manager.authorizationStatus == .authorizedAlways
    }

    /// Where the Mac is, with the town's name.
    func place() async throws(WeatherError) -> WeatherPlace {
        if let found, Date().timeIntervalSince(found.time) < Self.lifetime { return found.place }
        guard await requestPermission() else { throw isDenied ? .locationDenied : .noLocation }
        let result = await withCheckedContinuation { continuation in
            waiting.append(continuation)
            guard waiting.count == 1 else { return }
            request += 1
            let this = request
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: Self.fixWait)
                guard let self, self.request == this else { return }
                self.finish(.failure(.noLocation))
            }
        }
        let location = try result.get()
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude).rounded
        // Named from the rounded coordinate too: no finer than the forecast needs goes to Apple either.
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)).first
        let place = WeatherPlace(name: placemark?.locality ?? placemark?.name ?? "Current location", coordinate: coordinate,
                                 timeZoneID: placemark?.timeZone?.identifier, countryCode: placemark?.isoCountryCode)
        found = (place, Date())
        return place
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated { finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated { finish(.failure(denied ? .locationDenied : .noLocation)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Delegate calls come on the main thread, where the manager was made; it's read as this object's own.
        MainActor.assumeIsolated {
            guard self.manager.authorizationStatus != .notDetermined else { return }
            resumeAuthorizationWaiters()
        }
    }

    /// Each waiter is resumed once: the list is emptied as it's answered, by the system or by the timeout.
    private func resumeAuthorizationWaiters() {
        let waiters = authorizationWaiters
        authorizationWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func finish(_ result: Result<CLLocation, WeatherError>) {
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume(returning: result) }
    }
}

/// Place suggestions as someone types a city's name, from Apple Maps.
@MainActor @Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    /// The suggestion as a place: its coordinate and time zone, from Maps.
    func place(for suggestion: MKLocalSearchCompletion) async -> WeatherPlace? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion)).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return WeatherPlace(name: item.placemark.locality ?? suggestion.title, coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                            timeZoneID: item.timeZone?.identifier, countryCode: item.placemark.isoCountryCode)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { suggestions = Array(self.completer.results.prefix(6)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}

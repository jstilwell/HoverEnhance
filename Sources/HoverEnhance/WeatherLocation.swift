import CoreLocation
import Foundation
import MapKit

/// A named place, with the time zone its hours are told in.
struct WeatherPlace: Codable, Equatable, Hashable, Sendable {
    var name: String
    var coordinate: Coordinate
    var timeZoneID: String?

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
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private static let lifetime: TimeInterval = 30 * 60

    override init() {
        super.init()
        manager.delegate = self
        // A forecast covers kilometers; finer would only cost power and privacy.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }

    /// Asks for permission if it hasn't been asked, and says whether it was given.
    func requestPermission() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        return manager.authorizationStatus == .authorizedAlways
    }

    /// Where the Mac is, with the town's name.
    func place() async throws(WeatherError) -> WeatherPlace {
        if let found, Date().timeIntervalSince(found.time) < Self.lifetime { return found.place }
        guard await requestPermission() else { throw .locationDenied }
        let location = await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { manager.requestLocation() }
        }
        guard let location else { throw .noLocation }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.locality ?? placemark?.name ?? "Current location"
        let place = WeatherPlace(name: name, coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                                 timeZoneID: placemark?.timeZone?.identifier)
        found = (place, Date())
        return place
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        MainActor.assumeIsolated { finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Delegate calls come on the main thread, where the manager was made; it's read as this object's own.
        MainActor.assumeIsolated {
            guard self.manager.authorizationStatus != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    private func finish(_ location: CLLocation?) {
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume(returning: location) }
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
                            timeZoneID: item.timeZone?.identifier)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { suggestions = Array(self.completer.results.prefix(6)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}

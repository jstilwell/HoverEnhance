import CoreLocation
import Foundation

/// Download and upload speeds on the connection in use, a sample a second while the popup is open. The
/// last minute is kept between hovers, so the chart isn't empty each time.
@MainActor
final class NetworkTraffic {
    static let shared = NetworkTraffic()
    nonisolated static let window: TimeInterval = 60

    struct Sample: Sendable, Equatable {
        var time: Date
        /// Bytes per second.
        var received: Double
        var sent: Double
    }

    private(set) var samples: [Sample] = []
    private var last: (interface: String, counters: InterfaceCounters, time: Date)?

    /// Reads the counters and adds a sample, if there's an earlier reading of the same interface to compare.
    func sample(_ interface: String, counters: InterfaceCounters?, at time: Date = Date()) {
        defer { samples.removeAll { time.timeIntervalSince($0.time) > Self.window } }
        guard let counters else {
            last = nil
            return
        }
        if let last, last.interface != interface { samples.removeAll() }
        if let last, last.interface == interface, let rate = Self.rate(from: last.counters, to: counters, over: time.timeIntervalSince(last.time)) {
            samples.append(Sample(time: time, received: rate.received, sent: rate.sent))
        }
        last = (interface, counters, time)
    }

    /// Bytes per second between two readings, or nil when they're too close or too far apart to mean
    /// anything now, or the counters went back (the interface was reset).
    nonisolated static func rate(from old: InterfaceCounters, to new: InterfaceCounters, over seconds: TimeInterval) -> (received: Double, sent: Double)? {
        guard seconds >= 0.25, seconds <= 5, new.received >= old.received, new.sent >= old.sent else { return nil }
        return (Double(new.received - old.received) / seconds, Double(new.sent - old.sent) / seconds)
    }
}

/// What the network popup shows, kept up to date while it's open.
@MainActor @Observable
final class NetworkPopupModel {
    enum PublicState: Equatable {
        /// Turned off in Settings.
        case off
        case loading
        case found(PublicAddress)
        case failed
    }

    enum NameAccess: Equatable {
        /// The name is shown, or there's no Wi-Fi network to name.
        case notNeeded
        /// Location Services hasn't been asked yet.
        case canAsk
        case denied
    }

    private(set) var snapshot: NetworkSnapshot
    private(set) var publicState: PublicState
    private(set) var traffic: [NetworkTraffic.Sample]
    private(set) var nameAccess: NameAccess = .notNeeded
    @ObservationIgnored private let looksUpPublicAddress: Bool
    @ObservationIgnored private let reader: @Sendable () -> NetworkSnapshot

    init(settings: AppSettings, reader: @escaping @Sendable () -> NetworkSnapshot = NetworkReader.snapshot) {
        looksUpPublicAddress = settings.networkLooksUpPublicAddress
        self.reader = reader
        snapshot = NetworkSnapshot()
        publicState = settings.networkLooksUpPublicAddress ? .loading : .off
        traffic = NetworkTraffic.shared.samples
    }

    /// Already showing these, for tests and for checking the popup's look.
    init(showing snapshot: NetworkSnapshot, publicState: PublicState, traffic: [NetworkTraffic.Sample], nameAccess: NameAccess = .notNeeded) {
        self.snapshot = snapshot
        self.publicState = publicState
        self.traffic = traffic
        self.nameAccess = nameAccess
        looksUpPublicAddress = false
        reader = { snapshot }
    }

    /// What identifies the network for the public address: another router, Wi-Fi network, or VPN
    /// probably means another address.
    var networkKey: String {
        [snapshot.primary?.interface, snapshot.addresses.router, snapshot.wifi?.ssid, snapshot.vpnInterface].map { $0 ?? "-" }.joined(separator: "|")
    }

    /// Reads the network, and the public address if it's kept. Returns once there's something to show.
    func load() async {
        let reader = reader
        snapshot = await Task.detached { reader() }.value
        updateNameAccess()
        sampleTraffic()
        if looksUpPublicAddress, let kept = PublicAddressService.shared.kept(for: networkKey) {
            publicState = .found(kept)
        }
    }

    /// Keeps the popup current until it closes: traffic every second, the rest every few.
    func run() async {
        if looksUpPublicAddress, case .loading = publicState { Task { await lookUpPublicAddress() } }
        var tick = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            tick += 1
            if tick % 3 == 0 {
                let reader = reader
                let key = networkKey
                snapshot = await Task.detached { reader() }.value
                updateNameAccess()
                if looksUpPublicAddress, networkKey != key {
                    publicState = .loading
                    Task { await lookUpPublicAddress() }
                }
            }
            sampleTraffic()
        }
    }

    func retryPublicAddress() {
        publicState = .loading
        Task { await lookUpPublicAddress() }
    }

    /// Asks for Location Services, which macOS requires before it shares the Wi-Fi network's name.
    func askForName() {
        Task {
            _ = await CurrentLocation.shared.requestPermission()
            let reader = reader
            snapshot = await Task.detached { reader() }.value
            updateNameAccess()
        }
    }

    private func lookUpPublicAddress() async {
        let key = networkKey
        let address = await PublicAddressService.shared.lookUp(for: key)
        guard key == networkKey else { return }
        publicState = address.map { .found($0) } ?? .failed
    }

    private func sampleTraffic() {
        guard let interface = snapshot.primary?.interface else { return }
        let counters = InterfaceCounters.read()[interface]
        NetworkTraffic.shared.sample(interface, counters: counters)
        traffic = NetworkTraffic.shared.samples
    }

    private func updateNameAccess() {
        guard let wifi = snapshot.wifi, wifi.isAssociated, wifi.ssid == nil else {
            nameAccess = .notNeeded
            return
        }
        nameAccess = switch CLLocationManager().authorizationStatus {
        case .notDetermined: .canAsk
        default: .denied
        }
    }
}

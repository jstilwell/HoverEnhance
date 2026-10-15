import CoreWLAN
import Foundation
import SystemConfiguration

/// What the Mac's network looks like right now, read from the system without contacting anything.
struct NetworkSnapshot: Sendable, Equatable {
    /// The connection traffic goes out on, or nil when there's none.
    var primary: Connection?
    /// Wi-Fi, when it's on, whether or not it's the connection in use.
    var wifi: WiFi?
    /// Addresses on the connection in use.
    var addresses = Addresses()
    /// The name the Mac answers to on the local network, "Jesses-Mac.local".
    var localHostName: String?
    /// The tunnel traffic goes through, when a VPN carries it, as "utun4".
    var vpnInterface: String?

    struct Connection: Sendable, Equatable {
        enum Kind: Sendable, Equatable { case wifi, ethernet, other }
        /// The BSD name, as "en0".
        var interface: String
        var kind: Kind
        /// What System Settings calls it: "Ethernet", "Wi-Fi", "Thunderbolt Bridge".
        var name: String
        /// Bits per second the link was set up at, for a wired one.
        var linkSpeed: UInt64?
    }

    struct Addresses: Sendable, Equatable {
        var ipv4: String?
        var subnetMask: String?
        var router: String?
        /// Global IPv6 addresses, without link-local ones.
        var ipv6: [String] = []
        var dnsServers: [String] = []
        var searchDomains: [String] = []
    }

    struct WiFi: Sendable, Equatable {
        var interface: String
        /// The network's name. macOS shares it only with apps allowed Location Services.
        var ssid: String?
        /// dBm, as -52.
        var rssi: Int
        /// dBm, as -90.
        var noise: Int
        /// Mbps the Mac last sent at.
        var transmitRate: Double
        var channel: Int?
        var band: Band?
        /// MHz.
        var channelWidth: Int?
        var standard: Standard?
        var security: Security?
        /// Whether it's joined to a network, rather than only switched on.
        var isAssociated: Bool { rssi != 0 }

        enum Band: Sendable, Equatable {
            case ghz2, ghz5, ghz6
            var name: String {
                switch self {
                case .ghz2: "2.4 GHz"
                case .ghz5: "5 GHz"
                case .ghz6: "6 GHz"
                }
            }
        }
    }

    var isOnline: Bool { primary != nil && addresses.router != nil }
}

// MARK: - Words

extension NetworkSnapshot.WiFi {
    /// How strong the signal is, in Apple's own steps: about -50 dBm and up is excellent.
    enum Quality: Int, Comparable, Sendable {
        case weak, fair, good, excellent

        init(rssi: Int) {
            self = if rssi >= -55 { .excellent } else if rssi >= -67 { .good } else if rssi >= -75 { .fair } else { .weak }
        }

        var name: String {
            switch self {
            case .excellent: "Excellent"
            case .good: "Good"
            case .fair: "Fair"
            case .weak: "Weak"
            }
        }

        /// Bars on the Wi-Fi symbol, 1 to 3, as the menu bar shows.
        var bars: Int { max(rawValue, 1) }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var quality: Quality { Quality(rssi: rssi) }

    /// Signal over noise, in dB: above 40 is excellent, under 15 struggles.
    var signalToNoise: Int { rssi - noise }

    enum Standard: Int, Sendable, Equatable {
        case a = 1, b, g, n, ac, ax, be

        /// "Wi-Fi 6", or the IEEE name for ones from before the numbering.
        var name: String {
            switch self {
            case .be: "Wi-Fi 7"
            case .ax: "Wi-Fi 6"
            case .ac: "Wi-Fi 5"
            case .n: "Wi-Fi 4"
            case .a: "802.11a"
            case .b: "802.11b"
            case .g: "802.11g"
            }
        }

        var ieee: String {
            switch self {
            case .a: "802.11a"
            case .b: "802.11b"
            case .g: "802.11g"
            case .n: "802.11n"
            case .ac: "802.11ac"
            case .ax: "802.11ax"
            case .be: "802.11be"
            }
        }
    }

    enum Security: Sendable, Equatable {
        case open, wep, wpa, wpa2, wpa3, wpa3Transition, enterprise, wpa2Enterprise, wpa3Enterprise, enhancedOpen

        /// From CoreWLAN's `CWSecurity` raw values, which newer SDKs extend.
        init?(coreWLAN raw: Int) {
            switch raw {
            case 0: self = .open
            case 1, 6: self = .wep
            case 2, 3: self = .wpa
            case 4, 5: self = .wpa2
            case 7, 8, 10: self = .enterprise
            case 9: self = .wpa2Enterprise
            case 11: self = .wpa3
            case 12: self = .wpa3Enterprise
            case 13: self = .wpa3Transition
            case 14, 15: self = .enhancedOpen
            default: return nil
            }
        }

        var name: String {
            switch self {
            case .open: "None"
            case .wep: "WEP"
            case .wpa: "WPA Personal"
            case .wpa2: "WPA2 Personal"
            case .wpa3: "WPA3 Personal"
            case .wpa3Transition: "WPA2/WPA3 Personal"
            case .enterprise: "Enterprise"
            case .wpa2Enterprise: "WPA2 Enterprise"
            case .wpa3Enterprise: "WPA3 Enterprise"
            case .enhancedOpen: "Enhanced Open"
            }
        }

        /// Open networks and WEP let others on the network read what isn't otherwise encrypted.
        var isWeak: Bool { self == .open || self == .wep }
    }
}

enum NetworkWords {
    /// "1 Gbps", "358 Mbps", from bits per second.
    static func linkSpeed(bitsPerSecond bits: Double) -> String {
        if bits >= 1e9 {
            let gigabits = bits / 1e9
            return (gigabits.rounded() == gigabits ? String(Int(gigabits)) : String(format: "%.1f", gigabits)) + " Gbps"
        }
        return "\(Int((bits / 1e6).rounded())) Mbps"
    }

    /// "12.4 MB/s", "340 KB/s", "0 KB/s", in decimal units as Activity Monitor shows them.
    static func rate(bytesPerSecond bytes: Double) -> String {
        switch bytes {
        case 1e9...: String(format: "%.1f GB/s", bytes / 1e9)
        case 1e7...: String(format: "%.0f MB/s", bytes / 1e6)
        case 1e6...: String(format: "%.1f MB/s", bytes / 1e6)
        default: String(format: "%.0f KB/s", bytes / 1e3)
        }
    }

    /// 24 for "255.255.255.0", or nil for a mask that isn't one run of ones.
    static func prefixLength(ofMask mask: String) -> Int? {
        let parts = mask.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        let bits = parts.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let ones = bits.leadingZeroBitCount == 0 ? (~bits).leadingZeroBitCount : 0
        // All ones after the leading run would leave zeros: anything else isn't a valid mask.
        guard ones == 32 || bits << UInt32(ones) == 0 else { return nil }
        return ones
    }
}

// MARK: - Reading

/// Reads a `NetworkSnapshot`. Each call asks configd and the Wi-Fi driver, so call it off the main thread.
enum NetworkReader {
    static func snapshot() -> NetworkSnapshot {
        var snapshot = NetworkSnapshot()
        guard let store = SCDynamicStoreCreate(nil, "HoverEnhance" as CFString, nil, nil) else { return snapshot }
        func value(_ key: String) -> [String: Any]? { SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] }

        let global = value("State:/Network/Global/IPv4")
        var primaryName = global?["PrimaryInterface"] as? String
        snapshot.addresses.router = global?["Router"] as? String
        if let name = primaryName, isTunnel(name) {
            // A VPN carries the traffic; describe the connection it rides on.
            snapshot.vpnInterface = name
            primaryName = physicalInterface(in: store) ?? name
        }
        if let dns = value("State:/Network/Global/DNS") {
            snapshot.addresses.dnsServers = dns["ServerAddresses"] as? [String] ?? []
            snapshot.addresses.searchDomains = dns["SearchDomains"] as? [String] ?? []
        }
        snapshot.localHostName = SCDynamicStoreCopyLocalHostName(store).map { "\($0 as String).local" }

        let wifi = CWWiFiClient.shared().interface()
        let wifiName = wifi?.interfaceName
        if let name = primaryName {
            let ipv4 = value("State:/Network/Interface/\(name)/IPv4")
            snapshot.addresses.ipv4 = (ipv4?["Addresses"] as? [String])?.first
            snapshot.addresses.subnetMask = (ipv4?["SubnetMasks"] as? [String])?.first
            let ipv6 = value("State:/Network/Interface/\(name)/IPv6")?["Addresses"] as? [String] ?? []
            snapshot.addresses.ipv6 = ipv6.filter { !$0.lowercased().hasPrefix("fe80") }
            // With a VPN, the tunnel's router is the one in the global state; the physical one's is the network's.
            if snapshot.vpnInterface != nil {
                snapshot.addresses.router = routerOf(interface: name, in: store) ?? snapshot.addresses.router
            }
            let kind: NetworkSnapshot.Connection.Kind = name == wifiName ? .wifi : isEthernet(name) ? .ethernet : .other
            snapshot.primary = NetworkSnapshot.Connection(
                interface: name, kind: kind, name: displayName(of: name) ?? (kind == .wifi ? "Wi-Fi" : name),
                linkSpeed: kind == .wifi ? nil : InterfaceCounters.read()[name]?.baudRate.flatMap { $0 > 0 ? $0 : nil })
        }
        if let wifi, let name = wifiName, wifi.powerOn() {
            let channel = wifi.wlanChannel()
            snapshot.wifi = NetworkSnapshot.WiFi(
                interface: name, ssid: wifi.ssid(), rssi: wifi.rssiValue(), noise: wifi.noiseMeasurement(),
                transmitRate: wifi.transmitRate(), channel: channel.map(\.channelNumber),
                band: channel.flatMap { band(raw: $0.channelBand.rawValue) },
                channelWidth: channel.flatMap { width(raw: $0.channelWidth.rawValue) },
                standard: NetworkSnapshot.WiFi.Standard(rawValue: wifi.activePHYMode().rawValue),
                security: NetworkSnapshot.WiFi.Security(coreWLAN: wifi.security().rawValue))
        }
        return snapshot
    }

    static func isTunnel(_ interface: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap"].contains { interface.hasPrefix($0) }
    }

    static func band(raw: Int) -> NetworkSnapshot.WiFi.Band? {
        switch raw {
        case 1: .ghz2
        case 2: .ghz5
        case 3: .ghz6
        default: nil
        }
    }

    static func width(raw: Int) -> Int? {
        switch raw {
        case 1: 20
        case 2: 40
        case 3: 80
        case 4: 160
        case 5: 320
        default: nil
        }
    }

    /// The first service's interface, in the order set in System Settings, that has an address.
    private static func physicalInterface(in store: SCDynamicStore) -> String? {
        guard let order = (SCDynamicStoreCopyValue(store, "Setup:/Network/Global/IPv4" as CFString) as? [String: Any])?["ServiceOrder"] as? [String] else { return nil }
        for service in order {
            guard let state = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(service)/IPv4" as CFString) as? [String: Any],
                  let name = state["InterfaceName"] as? String, !isTunnel(name), state["Addresses"] != nil else { continue }
            return name
        }
        return nil
    }

    private static func routerOf(interface: String, in store: SCDynamicStore) -> String? {
        let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String] ?? []
        for key in keys {
            guard let state = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  state["InterfaceName"] as? String == interface else { continue }
            return state["Router"] as? String
        }
        return nil
    }

    private static func networkInterface(named name: String) -> SCNetworkInterface? {
        (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface])?.first { SCNetworkInterfaceGetBSDName($0) as String? == name }
    }

    private static func displayName(of name: String) -> String? {
        networkInterface(named: name).flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? }
    }

    private static func isEthernet(_ name: String) -> Bool {
        networkInterface(named: name).flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? } == (kSCNetworkInterfaceTypeEthernet as String)
    }
}

/// Bytes each interface has moved since the Mac started, and its link speed.
struct InterfaceCounters: Sendable, Equatable {
    var received: UInt64
    var sent: UInt64
    var baudRate: UInt64?

    /// Every interface's counters, by BSD name, from the routing socket's 64-bit interface list.
    static func read() -> [String: InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }
        var counters: [String: InterfaceCounters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(message.ifm_index), &name) != nil {
                        let data = message.ifm_data
                        counters[String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)] = InterfaceCounters(received: data.ifi_ibytes, sent: data.ifi_obytes,
                                                                            baudRate: data.ifi_baudrate)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return counters
    }
}

/// The menu bar items whose popups describe the Mac itself, told apart by their identifiers. macOS 27
/// hosts them in MenuBarAgent; earlier versions, in Control Center.
enum SystemMenuExtra: String, Sendable {
    case network = "com.apple.menuextra.wifi"

    static let hosts: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"]

    init?(_ info: HoverInfo) {
        guard let bundleID = info.bundleID, Self.hosts.contains(bundleID), info.subrole == "AXMenuExtra",
              let identifier = info.identifier, let extra = Self(rawValue: identifier) else { return nil }
        self = extra
    }
}

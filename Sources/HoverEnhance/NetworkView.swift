import AppKit
import Charts
import SwiftUI

/// The network popup: the connection in use, its traffic, its addresses here and on the internet, and the
/// Wi-Fi signal.
struct NetworkPopupView: View {
    let model: NetworkPopupModel
    let openSettings: @MainActor () -> Void

    static let width: CGFloat = 600

    @State private var copied: String?

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: 0) {
            NetworkHeader(snapshot: snapshot, latest: model.traffic.last)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
            if snapshot.primary != nil {
                TrafficChart(samples: model.traffic)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                LocalAddresses(snapshot: snapshot, copied: $copied)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(width: Self.width / 2, alignment: .topLeading)
                Divider()
                InternetSection(state: model.publicState, retry: model.retryPublicAddress, openSettings: openSettings, copied: $copied)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if let wifi = snapshot.wifi, wifi.isAssociated {
                Divider()
                WiFiSection(wifi: wifi, isPrimary: snapshot.primary?.kind == .wifi, nameAccess: model.nameAccess,
                            askForName: model.askForName)
                    .padding(12)
            }
            Divider()
            NetworkFooter(showsPublicCredit: model.publicState != .off)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .frame(width: Self.width)
        .task { await model.run() }
    }
}

// MARK: - Header

private struct NetworkHeader: View {
    let snapshot: NetworkSnapshot
    let latest: NetworkTraffic.Sample?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            symbol
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(snapshot.isOnline ? Color.accentColor : .secondary)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                    if snapshot.vpnInterface != nil {
                        Badge(text: "VPN", symbol: "lock.fill", color: .green)
                    }
                }
            }
            Spacer(minLength: 8)
            if snapshot.primary != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    Speed(symbol: "arrow.down", bytes: latest?.received, color: .blue)
                    Speed(symbol: "arrow.up", bytes: latest?.sent, color: .orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var symbol: some View {
        switch snapshot.primary?.kind {
        case .wifi?:
            let bars = snapshot.wifi?.quality.bars ?? 3
            Image(systemName: "wifi", variableValue: Double(bars) / 3)
        case .ethernet?:
            Image(systemName: "cable.connector.horizontal")
        case .other?:
            Image(systemName: "network")
        case nil:
            Image(systemName: "wifi.slash")
        }
    }

    private var title: String {
        guard let primary = snapshot.primary else { return "Not connected" }
        if primary.kind == .wifi { return snapshot.wifi?.ssid ?? "Wi-Fi" }
        return primary.name
    }

    private var subtitle: String {
        guard let primary = snapshot.primary else { return "No network connection" }
        var parts: [String] = [snapshot.isOnline ? "Connected" : "No router"]
        if primary.kind == .wifi, let wifi = snapshot.wifi {
            parts.append("\(wifi.quality.name) signal")
            if let band = wifi.band { parts.append(band.name) }
        } else if let speed = primary.linkSpeed {
            parts.append(NetworkWords.linkSpeed(bitsPerSecond: Double(speed)))
        }
        return parts.joined(separator: " · ")
    }
}

private struct Speed: View {
    let symbol: String
    let bytes: Double?
    let color: Color

    var body: some View {
        Label {
            Text(bytes.map { NetworkWords.rate(bytesPerSecond: $0) } ?? "–")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: symbol).foregroundStyle(color).fontWeight(.bold)
        }
        .labelStyle(.titleAndIcon)
        .frame(minWidth: 110, alignment: .trailing)
    }
}

private struct Badge: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Traffic

/// The last minute's download and upload speeds.
private struct TrafficChart: View {
    let samples: [NetworkTraffic.Sample]

    var body: some View {
        let now = samples.last?.time ?? Date()
        let peak = max(samples.map { max($0.received, $0.sent) }.max() ?? 0, 50_000)
        ZStack(alignment: .topLeading) {
            Chart {
                ForEach(samples, id: \.time) { sample in
                    AreaMark(x: .value("Seconds", sample.time.timeIntervalSince(now)), y: .value("Down", sample.received),
                             series: .value("Direction", "Down"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Seconds", sample.time.timeIntervalSince(now)), y: .value("Down", sample.received),
                             series: .value("Direction", "Down"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    LineMark(x: .value("Seconds", sample.time.timeIntervalSince(now)), y: .value("Up", sample.sent),
                             series: .value("Direction", "Up"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
            .chartXScale(domain: -NetworkTraffic.window ... 0)
            .chartYScale(domain: 0 ... peak * 1.15)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Last minute")
                Spacer()
                if samples.count >= 2 {
                    Text("Peak \(NetworkWords.rate(bytesPerSecond: samples.map { max($0.received, $0.sent) }.max() ?? 0))")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 5)
            if samples.count < 2 {
                Text("Measuring…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Traffic over the last minute")
    }
}

// MARK: - Addresses

/// A label and a value that copies itself when clicked.
private struct CopyRow: View {
    let label: String
    let value: String
    var detail: String?
    /// Addresses are set in monospaced type, so their digits line up; names in the usual type.
    var isAddress = true
    @Binding var copied: String?

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = label + value
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(isAddress ? .system(.callout, design: .monospaced) : .body)
                        .lineLimit(isAddress ? 1 : 2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: copied == label + value ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(copied == label + value ? Color.green : Color.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied == label + value ? "Copied" : "Copy \(label.lowercased())")
    }
}

private struct LocalAddresses: View {
    let snapshot: NetworkSnapshot
    @Binding var copied: String?

    var body: some View {
        let addresses = snapshot.addresses
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "On this network", symbol: "house")
            if let ipv4 = addresses.ipv4 {
                CopyRow(label: "IP address", value: ipv4,
                        detail: addresses.subnetMask.flatMap(NetworkWords.prefixLength(ofMask:)).map { "Subnet /\($0) · \(snapshot.primary?.interface ?? "")" },
                        copied: $copied)
            }
            if let router = addresses.router {
                CopyRow(label: "Router", value: router, copied: $copied)
            }
            if let first = addresses.dnsServers.first {
                CopyRow(label: "DNS", value: first,
                        detail: addresses.dnsServers.count > 1 ? addresses.dnsServers.dropFirst().prefix(2).joined(separator: ", ") : nil,
                        copied: $copied)
            }
            if let ipv6 = addresses.ipv6.first {
                CopyRow(label: "IPv6", value: ipv6, copied: $copied)
            }
            if let name = snapshot.localHostName {
                CopyRow(label: "This Mac", value: name, isAddress: false, copied: $copied)
            }
            if addresses.ipv4 == nil, addresses.ipv6.isEmpty {
                Text("No address on this network yet.").foregroundStyle(.secondary)
            }
        }
    }
}

private struct InternetSection: View {
    let state: NetworkPopupModel.PublicState
    let retry: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    @Binding var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "On the internet", symbol: "globe")
            switch state {
            case .off:
                Text("Looking up your public address is off.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings", action: openSettings).controlSize(.small)
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking up…").foregroundStyle(.secondary)
                }
            case .failed:
                Text("The internet isn't answering.").foregroundStyle(.secondary)
                Button("Try Again", action: retry).controlSize(.small)
            case .found(let address):
                CopyRow(label: "Public IP", value: address.ip, copied: $copied)
                if let provider = address.provider {
                    CopyRow(label: "Provider", value: provider, detail: address.asn.map { "AS\($0)" }, isAddress: false, copied: $copied)
                }
                if let place = address.place {
                    CopyRow(label: "Seen from", value: place, isAddress: false, copied: $copied)
                }
                if let latency = address.latency {
                    CopyRow(label: "Latency", value: "\(Int(latency.rounded())) ms",
                            detail: address.edge.map { "To Cloudflare \($0)" }, isAddress: false, copied: $copied)
                }
            }
        }
    }
}

// MARK: - Wi-Fi

private struct WiFiSection: View {
    let wifi: NetworkSnapshot.WiFi
    /// Whether traffic goes over Wi-Fi, rather than its being joined alongside another connection.
    let isPrimary: Bool
    let nameAccess: NetworkPopupModel.NameAccess
    let askForName: @MainActor () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionHeading(title: isPrimary ? "Wi-Fi" : "Wi-Fi, also joined", symbol: "wifi")
                if !isPrimary, let ssid = wifi.ssid {
                    Text(ssid).font(.caption.weight(.semibold)).lineLimit(1)
                }
                Spacer()
                switch nameAccess {
                case .notNeeded:
                    EmptyView()
                case .canAsk:
                    Button("Show Network Name", action: askForName).controlSize(.small)
                        .help("macOS shares the Wi-Fi network's name only with apps allowed Location Services")
                case .denied:
                    Button("Show Network Name") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                    }
                    .controlSize(.small)
                    .help("macOS shares the Wi-Fi network's name only with apps allowed Location Services")
                }
            }
            .padding(.horizontal, 6)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                Tile(title: "Signal", symbol: "antenna.radiowaves.left.and.right", value: "\(wifi.rssi) dBm", note: wifi.quality.name) {
                    // -90 dBm is all but gone; -30 is next to the router.
                    LevelBar(fraction: min(max(Double(wifi.rssi + 90) / 60, 0), 1), colors: [.red, .orange, .yellow, .green])
                }
                Tile(title: "Noise", symbol: "waveform", value: "\(wifi.noise) dBm", note: "\(wifi.signalToNoise) dB above it")
                if let channel = wifi.channel {
                    Tile(title: "Channel", symbol: "dot.radiowaves.right", value: "\(channel)",
                         note: [wifi.band?.name, wifi.channelWidth.map { "\($0) MHz" }].compactMap { $0 }.joined(separator: " · "))
                }
                Tile(title: "Link rate", symbol: "speedometer", value: "\(Int(wifi.transmitRate)) Mbps", note: "Sending now")
                if let standard = wifi.standard {
                    Tile(title: "Standard", symbol: "wifi.router", value: standard.name, note: standard.ieee)
                }
                if let security = wifi.security {
                    Tile(title: "Security", symbol: security.isWeak ? "lock.open" : "lock", value: security.name,
                         note: security.isWeak ? "Others nearby can see traffic" : "Encrypted")
                }
            }
        }
    }
}

// MARK: - Footer

private struct NetworkFooter: View {
    let showsPublicCredit: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsPublicCredit {
                HStack(spacing: 3) {
                    Text("Public address from")
                    Link("addr.fyi", destination: PublicAddressService.page)
                }
                Text("·")
            }
            Button("Network Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)
            }
            .buttonStyle(.link)
            Spacer()
            Text("Click a value to copy it")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
}

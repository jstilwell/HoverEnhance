import Charts
import SwiftUI

/// The weather popup: the forecast laid out as a dashboard, or why there isn't one.
struct WeatherPopupView: View {
    let model: WeatherPopupModel
    /// Sets the location to where the Mac is and loads again.
    let useCurrentLocation: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    let retry: @MainActor () -> Void

    static let width: CGFloat = 660

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView().controlSize(.small).frame(width: 120, height: 60)
            case .report(let report, let place):
                WeatherDashboard(report: report, place: place, isCurrentLocation: model.isCurrentLocation, units: model.units,
                                 hidden: model.hidden, isRefreshing: model.isRefreshing)
            case .problem(let problem):
                WeatherProblemView(problem: problem, provider: model.provider, useCurrentLocation: useCurrentLocation,
                                   openSettings: openSettings, retry: retry)
            }
        }
    }
}

// MARK: - Dashboard

private struct WeatherDashboard: View {
    let report: WeatherReport
    let place: WeatherPlace
    let isCurrentLocation: Bool
    let units: WeatherUnits
    let hidden: Set<WeatherSection>
    let isRefreshing: Bool

    private var times: WeatherTimes { WeatherTimes(timeZone: report.timeZone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WeatherHeader(report: report, place: place, isCurrentLocation: isCurrentLocation, units: units, times: times)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)
            if !hidden.contains(.hourly), report.upcomingHours(25).count >= 2 {
                Divider()
                HourlyStrip(hours: report.upcomingHours(25), units: units, times: times)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            let showsDaily = !hidden.contains(.daily) && !report.daily.isEmpty
            let showsDetails = !hidden.contains(.details) || (!hidden.contains(.airQuality) && report.air != nil)
            if showsDaily || showsDetails {
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    if showsDaily {
                        DailyList(report: report, units: units, times: times)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .frame(width: showsDetails ? WeatherPopupView.width / 2 : WeatherPopupView.width, alignment: .leading)
                    }
                    if showsDaily, showsDetails { Divider() }
                    if showsDetails {
                        DetailsGrid(report: report, units: units, times: times, showsDetails: !hidden.contains(.details),
                                    showsAir: !hidden.contains(.airQuality))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            if !hidden.contains(.alerts), !report.alerts.isEmpty {
                Divider()
                AlertList(alerts: report.alerts, times: times)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            Divider()
            Footer(report: report, times: times, isRefreshing: isRefreshing)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .frame(width: WeatherPopupView.width)
    }
}

/// Times written in the place's own time zone, which needn't be the Mac's.
struct WeatherTimes {
    let timeZone: TimeZone

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatter.timeZone = timeZone
        return formatter
    }

    /// "9 AM".
    func hour(_ date: Date) -> String { formatter("j").string(from: date) }
    /// "7:12 AM".
    func time(_ date: Date) -> String { formatter("jmm").string(from: date) }
    /// "Tue".
    func weekday(_ date: Date) -> String { formatter("EEE").string(from: date) }

    func isToday(_ date: Date, now: Date = Date()) -> Bool { calendar.isDate(date, inSameDayAs: now) }

    /// Whether the place keeps a different clock from the Mac's right now.
    var differsFromMac: Bool { timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT() }
}

private struct WeatherHeader: View {
    let report: WeatherReport
    let place: WeatherPlace
    let isCurrentLocation: Bool
    let units: WeatherUnits
    let times: WeatherTimes

    var body: some View {
        let current = report.current
        let today = report.daily.first { times.isToday($0.date) }
        HStack(alignment: .center, spacing: 14) {
            ConditionSymbol(name: current.condition.symbol(isDay: current.isDay), size: 44)
                .frame(width: 58)
            Text(units.degrees(current.temperature))
                .font(.system(size: 52, weight: .light, design: .rounded))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 3) {
                Text(current.condition.name).font(.title3.weight(.semibold))
                Text([current.feelsLike.map { "Feels like \(units.degrees($0))" },
                      today.map { "H \(units.degrees($0.high))  L \(units.degrees($0.low))" }]
                    .compactMap { $0 }.joined(separator: "  ·  "))
                    .foregroundStyle(.secondary)
                if let next = report.nextHourPrecipitation() {
                    Label(Self.describe(next, times: times), systemImage: next.isDry ? "umbrella" : "cloud.rain")
                        .font(.callout)
                        .foregroundStyle(next.isDry ? Color.secondary : Color.blue)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Group {
                    if isCurrentLocation {
                        Label(place.name, systemImage: "location.fill").labelStyle(.titleAndIcon)
                    } else {
                        Text(place.name)
                    }
                }
                .font(.headline)
                .lineLimit(1)
                if times.differsFromMac {
                    Text("\(times.time(Date())) there").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func describe(_ next: WeatherReport.NextHour, times: WeatherTimes) -> String {
        switch next {
        case .now(let until?): "Rain stopping around \(times.time(until))"
        case .now(nil): "Rain for the next hour"
        case .starting(let time): "Rain starting around \(times.time(time))"
        case .dry: "No rain in the next hour"
        case .chance(let percent): percent < 10 ? "Rain unlikely in the next hour" : "\(Int(percent))% chance of rain this hour"
        }
    }
}

private extension WeatherReport.NextHour {
    var isDry: Bool {
        switch self {
        case .dry: true
        case .chance(let percent): percent < 30
        case .now, .starting: false
        }
    }
}

/// A condition's symbol in its own colors. Its clouds are white, which in light mode would all but vanish,
/// so there they get a faint edge.
private struct ConditionSymbol: View {
    let name: String
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .shadow(color: colorScheme == .light ? .black.opacity(0.35) : .clear, radius: 0.8, y: 0.4)
    }
}

/// A tile or section's small capitals heading, as Weather has.
private struct SectionHeading: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title.uppercased(), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Next 24 hours

private struct HourlyStrip: View {
    let hours: [WeatherReport.Hour]
    let units: WeatherUnits
    let times: WeatherTimes

    /// A column every two hours, from now; the chart under them spans the same hours.
    private var columns: [WeatherReport.Hour] { hours.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) }
    private var span: ClosedRange<Double> { -1 ... Double(columns.count * 2 - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "Next 24 hours", symbol: "clock")
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, hour in
                    VStack(spacing: 6) {
                        Text(index == 0 ? "Now" : times.hour(hour.time))
                            .font(.caption.weight(index == 0 ? .semibold : .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        ConditionSymbol(name: hour.condition.symbol(isDay: hour.isDay), size: 17)
                            .frame(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Chart {
                ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                    AreaMark(x: .value("Hour", Double(index)), yStart: .value("Floor", lowest - 2), yEnd: .value("Temperature", shown(hour.temperature)))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.linearGradient(colors: [.orange.opacity(0.28), .orange.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Hour", Double(index)), y: .value("Temperature", shown(hour.temperature)))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    if index % 2 == 0 {
                        PointMark(x: .value("Hour", Double(index)), y: .value("Temperature", shown(hour.temperature)))
                            .symbolSize(18)
                            .foregroundStyle(.orange)
                            .annotation(position: .top, spacing: 3) {
                                Text(units.degrees(hour.temperature)).font(.caption.weight(.medium)).monospacedDigit()
                            }
                    }
                }
            }
            .chartXScale(domain: span)
            .chartYScale(domain: (lowest - 2) ... (highest + 4))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 62)
            if hours.contains(where: { ($0.precipitationChance ?? 0) >= 10 }) {
                Chart {
                    ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                        BarMark(x: .value("Hour", Double(index)), yStart: .value("None", 0), yEnd: .value("Chance", hour.precipitationChance ?? 0), width: .ratio(0.6))
                            .foregroundStyle(.blue.opacity(0.55))
                            .cornerRadius(2)
                    }
                }
                .chartXScale(domain: span)
                .chartYScale(domain: 0 ... 100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 18)
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, hour in
                        let chance = hour.precipitationChance ?? 0
                        Text(chance >= 10 ? "\(Int(chance))%" : " ")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func shown(_ celsius: Double) -> Double {
        units.temperature == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    private var lowest: Double { hours.map { shown($0.temperature) }.min() ?? 0 }
    private var highest: Double { hours.map { shown($0.temperature) }.max() ?? 0 }

    private var accessibilitySummary: String {
        "Next 24 hours: " + columns.map { "\(times.hour($0.time)) \(units.degrees($0.temperature)) \($0.condition.name)" }.joined(separator: ", ")
    }
}

// MARK: - Days

private struct DailyList: View {
    let report: WeatherReport
    let units: WeatherUnits
    let times: WeatherTimes

    private var days: [WeatherReport.Day] { Array(report.daily.drop { $0.date < times.calendar.startOfDay(for: Date()) }.prefix(10)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "\(days.count)-day forecast", symbol: "calendar")
            let low = days.map(\.low).min() ?? 0
            let high = days.map(\.high).max() ?? 1
            VStack(spacing: 10) {
                ForEach(days, id: \.date) { day in
                    HStack(spacing: 8) {
                        Text(times.isToday(day.date) ? "Today" : times.weekday(day.date))
                            .fontWeight(times.isToday(day.date) ? .semibold : .regular)
                            .frame(width: 46, alignment: .leading)
                        ConditionSymbol(name: day.condition.symbol(isDay: true), size: 15)
                            .frame(width: 22)
                        Text((day.precipitationChance ?? 0) >= 20 ? "\(Int(day.precipitationChance ?? 0))%" : "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 30, alignment: .leading)
                        Text(units.degrees(day.low)).foregroundStyle(.secondary).monospacedDigit().frame(width: 32, alignment: .trailing)
                        RangeBar(low: day.low, high: day.high, weekLow: low, weekHigh: high,
                                 now: times.isToday(day.date) ? report.current.temperature : nil)
                            .frame(height: 5)
                        Text(units.degrees(day.high)).monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(times.isToday(day.date) ? "Today" : times.weekday(day.date)): \(day.condition.name), low \(units.degrees(day.low)), high \(units.degrees(day.high))")
                }
            }
        }
    }
}

/// A day's low to high, against the whole forecast's, colored by temperature, as Weather draws it.
private struct RangeBar: View {
    let low: Double
    let high: Double
    let weekLow: Double
    let weekHigh: Double
    /// Today's current temperature, marked with a dot.
    var now: Double?

    var body: some View {
        GeometryReader { geometry in
            let span = max(weekHigh - weekLow, 1)
            let start = (low - weekLow) / span * geometry.size.width
            let end = (high - weekLow) / span * geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [Self.color(low), Self.color(high)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(end - start, 5))
                    .offset(x: start)
                if let now {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
                        .frame(width: 7, height: 7)
                        .offset(x: min(max((now - weekLow) / span * geometry.size.width - 3.5, start - 1), end - 6))
                }
            }
        }
    }

    /// From deep blue at freezing and below to red in the heat.
    static func color(_ celsius: Double) -> Color {
        let stops: [(Double, Color)] = [(-10, .indigo), (0, .blue), (10, .teal), (18, .green), (24, .yellow), (30, .orange), (36, .red)]
        guard let after = stops.firstIndex(where: { $0.0 >= celsius }) else { return .red }
        return after == 0 ? stops[0].1 : stops[after].1
    }
}

// MARK: - Details

private struct DetailsGrid: View {
    let report: WeatherReport
    let units: WeatherUnits
    let times: WeatherTimes
    let showsDetails: Bool
    let showsAir: Bool

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        let current = report.current
        let today = report.daily.first { times.isToday($0.date) }
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            if showsDetails {
                if let speed = current.windSpeed {
                    Tile(title: "Wind", symbol: "wind", value: units.wind(speed),
                         note: [current.windDirection.map { "From \(WeatherWords.compass($0))" }, current.windGust.map { "gusts \(units.wind($0))" }]
                            .compactMap { $0 }.joined(separator: ", ")) {
                        if let direction = current.windDirection {
                            // The arrow points where the wind blows to.
                            Image(systemName: "location.north.fill")
                                .rotationEffect(.degrees(direction + 180))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let humidity = current.humidity {
                    Tile(title: "Humidity", symbol: "humidity", value: "\(Int(humidity.rounded()))%",
                         note: current.dewPoint.map { "Dew point \(units.degrees($0))" })
                }
                if let uv = current.uvIndex ?? today?.uvIndexMax {
                    Tile(title: "UV index", symbol: "sun.max", value: "\(Int(uv.rounded()))", note: WeatherWords.uvLevel(uv)) {
                        LevelBar(fraction: min(uv / 11, 1), colors: [.green, .yellow, .orange, .red, .purple])
                    }
                }
                if let pressure = current.pressure {
                    let trend = report.pressureTrend()
                    Tile(title: "Pressure", symbol: "gauge.with.dots.needle.33percent", value: units.pressure(pressure),
                         note: trend.map { $0 == .rising ? "Rising" : $0 == .falling ? "Falling" : "Steady" })
                }
                if let visibility = current.visibility {
                    Tile(title: "Visibility", symbol: "eye", value: units.distance(visibility),
                         note: current.cloudCover.map { "\(Int($0.rounded()))% cloud cover" })
                }
                if let today, today.precipitation != nil || today.precipitationChance != nil {
                    Tile(title: "Precipitation", symbol: "drop",
                         value: today.precipitation.map { $0 < 0.1 ? "None" : units.precipitation($0) } ?? "\(Int(today.precipitationChance ?? 0))%",
                         note: today.precipitation != nil ? "Today" + (today.precipitationChance.map { ", \(Int($0))% chance" } ?? "") : "Chance today")
                }
                if let sunrise = today?.sunrise, let sunset = today?.sunset {
                    Tile(title: "Sun", symbol: "sunrise", value: "\(times.time(sunrise))  ·  \(times.time(sunset))",
                         note: "Daylight \(WeatherWords.duration(sunset.timeIntervalSince(sunrise)))")
                }
                let moon = MoonPhase(at: Date())
                Tile(title: "Moon", symbol: moon.symbol, value: moon.name, note: "\(Int((moon.illumination * 100).rounded()))% lit")
            }
            if showsAir, let air = report.air, let reading = Self.airReading(air) {
                Tile(title: "Air quality", symbol: "aqi.medium", value: "\(reading.index)  \(reading.name)",
                     note: air.pm25.map { "PM2.5 \(Int($0.rounded())) µg/m³" }) {
                    LevelBar(fraction: min(Double(reading.level) / 5 + 0.08, 1), colors: [.green, .yellow, .orange, .red, .purple, Color(red: 0.5, green: 0, blue: 0.13)])
                }
            }
        }
    }

    /// The US index where there is one, as most providers give; Europe's otherwise.
    static func airReading(_ air: WeatherReport.AirQuality) -> (index: Int, name: String, level: Int)? {
        if let index = air.usIndex {
            let category = WeatherWords.airQuality(us: index)
            return (index, category.name, category.level)
        }
        if let index = air.europeanIndex {
            let category = WeatherWords.airQuality(european: index)
            return (index, category.name, category.level)
        }
        return nil
    }
}

private struct Tile<Accessory: View>: View {
    let title: String
    let symbol: String
    let value: String
    var note: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionHeading(title: title, symbol: symbol)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                accessory()
            }
            if let note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

extension Tile where Accessory == EmptyView {
    init(title: String, symbol: String, value: String, note: String? = nil) {
        self.init(title: title, symbol: symbol, value: value, note: note) { EmptyView() }
    }
}

/// Where a reading falls on its scale, as a dot on a colored bar.
private struct LevelBar: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .offset(x: max(0, min(fraction, 1) * geometry.size.width - 3.5))
            }
        }
        .frame(width: 48, height: 5)
    }
}

// MARK: - Alerts and footer

private struct AlertList: View {
    let alerts: [WeatherAlert]
    let times: WeatherTimes

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(alerts.sorted { $0.severity > $1.severity }.prefix(3).enumerated()), id: \.offset) { _, alert in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Self.color(alert.severity))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(alert.title).fontWeight(.semibold).lineLimit(1)
                        Text([alert.ends.map { "Until \(times.weekday($0)) \(times.time($0))" }, alert.source]
                            .compactMap { $0 }.joined(separator: "  ·  "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let url = alert.url {
                        Link("Details", destination: url).font(.caption)
                    }
                }
            }
            if alerts.count > 3 {
                Text("and \(alerts.count - 3) more").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func color(_ severity: WeatherAlert.Severity) -> Color {
        switch severity {
        case .extreme: .purple
        case .severe: .red
        case .moderate: .orange
        case .minor, .unknown: .yellow
        }
    }
}

private struct Footer: View {
    let report: WeatherReport
    let times: WeatherTimes
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Link(report.provider.attribution.text, destination: report.provider.attribution.url)
            if report.provider == .openMeteo, report.air != nil {
                // Open-Meteo's air quality comes from Copernicus, which asks to be credited too.
                Text("·")
                Link("Air quality: Copernicus CAMS", destination: URL(string: "https://atmosphere.copernicus.eu/")!)
            }
            Spacer()
            if isRefreshing {
                ProgressView().controlSize(.mini)
            }
            Text("Updated \(Self.updated(report.fetched))")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    /// In the Mac's own time: it's when this Mac fetched it.
    static func updated(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Problems

private struct WeatherProblemView: View {
    let problem: WeatherError
    let provider: WeatherProviderID
    let useCurrentLocation: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    let retry: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { buttons }.padding(.top, 4)
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
    }

    private var symbol: String {
        switch problem {
        case .noLocation, .locationDenied: "location.slash"
        case .needsKey, .badKey: "key"
        case .offline: "wifi.slash"
        case .rateLimited, .unavailable, .unreadable: "cloud.sun"
        }
    }

    private var title: String {
        switch problem {
        case .noLocation: "Where should the weather be for?"
        case .locationDenied: "Location Services is off for HoverEnhance"
        case .needsKey: "\(provider.name) needs a key"
        case .badKey: "\(provider.name) didn't accept the key"
        case .offline: "No connection"
        case .rateLimited: "\(provider.name) asks to wait"
        case .unavailable, .unreadable: "\(provider.name) isn't answering"
        }
    }

    private var message: String {
        switch problem {
        case .noLocation: "Use where your Mac is, or choose a city. Nothing is looked up until you do."
        case .locationDenied: "Allow it in System Settings → Privacy & Security → Location Services, or choose a city instead."
        case .needsKey: "Add your free \(provider.name) key in Settings → Weather, or switch to Open-Meteo, which needs none."
        case .badKey: "Check the key in Settings → Weather. A new key can take a little while to start working."
        case .offline: "The forecast will load once your Mac is back online."
        case .rateLimited: "Your key has used its lookups for now. The forecast will load again in a while."
        case .unavailable(let status?): "It answered with an error (\(status)). Try again in a moment."
        case .unavailable(nil), .unreadable: "Try again in a moment, or choose another provider in Settings → Weather."
        }
    }

    @ViewBuilder private var buttons: some View {
        switch problem {
        case .noLocation:
            Button("Use Current Location", action: useCurrentLocation)
            Button("Choose a City…", action: openSettings)
        case .locationDenied:
            Button("Open Location Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
            }
            Button("Choose a City…", action: openSettings)
        case .needsKey, .badKey:
            Button("Open Weather Settings", action: openSettings)
        case .offline, .rateLimited, .unavailable, .unreadable:
            Button("Try Again", action: retry)
        }
    }
}

import MapKit
import SwiftUI

/// Settings → Weather: the forecast shown for the Weather menu bar item.
struct WeatherSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.weatherEnabled) {
                    Text("Show the forecast")
                    Text("When the cursor rests on the Weather item in the menu bar")
                }
            }
            Section {
                WeatherLocationPicker(choice: $settings.weatherLocation)
            } header: {
                Text("Location")
            } footer: {
                Footnote("Nothing is looked up until a location is set. It's sent to the provider rounded to about a kilometer.")
            }
            .disabled(!settings.weatherEnabled)
            Section {
                Picker("Provider", selection: $settings.weatherProvider) {
                    ForEach(WeatherProviderID.allCases) { Text($0.name).tag($0) }
                }
                Text(settings.weatherProvider.detail).font(.callout).foregroundStyle(.secondary)
                if settings.weatherProvider.needsKey {
                    WeatherKeyField(provider: settings.weatherProvider, location: settings.weatherLocation)
                        .id(settings.weatherProvider)
                }
            } header: {
                Text("Provider")
            } footer: {
                Footnote("Keys are kept in your keychain. Each provider has its own terms; HoverEnhance shows the credit each asks for.")
            }
            .disabled(!settings.weatherEnabled)
            Section {
                Picker("Temperature", selection: $settings.weatherUnits.temperature) {
                    ForEach(WeatherUnits.Temperature.allCases) { Text($0.label).tag($0) }
                }
                Picker("Wind", selection: $settings.weatherUnits.speed) {
                    ForEach(WeatherUnits.Speed.allCases) { Text($0.label).tag($0) }
                }
                Picker("Pressure", selection: $settings.weatherUnits.pressure) {
                    ForEach(WeatherUnits.Pressure.allCases) { Text($0.label).tag($0) }
                }
                Picker("Rain and snow", selection: $settings.weatherUnits.precipitation) {
                    ForEach(WeatherUnits.Precipitation.allCases) { Text($0.label).tag($0) }
                }
                Picker("Distance", selection: $settings.weatherUnits.distance) {
                    ForEach(WeatherUnits.Distance.allCases) { Text($0.label).tag($0) }
                }
                Button("Use Units for My Region") { settings.weatherUnits = .forLocale() }
                    .disabled(settings.weatherUnits == .forLocale())
            } header: {
                Text("Units")
            }
            .disabled(!settings.weatherEnabled)
            Section {
                ForEach(WeatherSection.allCases) { section in
                    Toggle(section.name, isOn: Binding(
                        get: { !settings.weatherHiddenSections.contains(section) },
                        set: { on in
                            if on { settings.weatherHiddenSections.remove(section) } else { settings.weatherHiddenSections.insert(section) }
                        }
                    ))
                }
                Toggle(isOn: $settings.weatherUsesNWSAlerts) {
                    Text("US alerts from the National Weather Service")
                    Text("For places in the US, when the provider has no alerts of its own. Sends the location to weather.gov too.")
                }
                .disabled(settings.weatherHiddenSections.contains(.alerts))
            } header: {
                Text("Show")
            }
            .disabled(!settings.weatherEnabled)
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: settingsHeight)
    }
}

/// Where the weather is for: the Mac's location, or a city found by name.
private struct WeatherLocationPicker: View {
    @Binding var choice: WeatherLocationChoice?
    @State private var search = PlaceSearch()
    @State private var lastPlace: WeatherPlace?
    @State private var current: CurrentStatus = .unknown

    private enum Mode: Hashable { case current, place }
    private enum CurrentStatus: Equatable { case unknown, finding, found(String), denied, failed }

    private var mode: Binding<Mode?> {
        Binding(
            get: {
                switch choice {
                case .current?: .current
                case .place?: .place
                case nil: nil
                }
            },
            set: { mode in
                switch mode {
                case .current?:
                    choice = .current
                    findCurrent()
                case .place?:
                    if let lastPlace { choice = .place(lastPlace) } else { choice = nil }
                case nil:
                    choice = nil
                }
            }
        )
    }

    var body: some View {
        Picker("Weather for", selection: mode) {
            Text("Current location").tag(Mode?.some(.current))
            Text("A city").tag(Mode?.some(.place))
        }
        .pickerStyle(.radioGroup)
        .onAppear {
            if case .place(let place)? = choice { lastPlace = place }
            if choice == .current { findCurrent() }
        }
        if choice == .current {
            switch current {
            case .unknown, .finding:
                HStack { ProgressView().controlSize(.small); Text("Finding your location…").foregroundStyle(.secondary) }
            case .found(let name):
                Label(name, systemImage: "location.fill").foregroundStyle(.secondary)
            case .denied:
                HStack {
                    Text("Location Services is off for HoverEnhance.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Location Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                    }
                }
            case .failed:
                Text("Your location couldn't be found just now.").foregroundStyle(.secondary)
            }
        } else {
            if let lastPlace, case .place = choice {
                Label(lastPlace.name, systemImage: "mappin.and.ellipse")
            }
            TextField("City", text: $search.query, prompt: Text("Search for a city"))
                .textFieldStyle(.roundedBorder)
            ForEach(search.suggestions, id: \.self) { suggestion in
                Button {
                    pick(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func findCurrent() {
        current = .finding
        Task {
            do throws(WeatherError) {
                current = .found(try await CurrentLocation.shared.place().name)
            } catch {
                current = error == .locationDenied ? .denied : .failed
            }
        }
    }

    private func pick(_ suggestion: MKLocalSearchCompletion) {
        Task {
            guard let place = await search.place(for: suggestion) else { return }
            lastPlace = place
            choice = .place(place)
            search.query = ""
        }
    }
}

/// A provider's key, kept in the keychain, with a way to try it.
private struct WeatherKeyField: View {
    let provider: WeatherProviderID
    let location: WeatherLocationChoice?
    @State private var key = ""
    @State private var test: TestState = .idle
    /// Why the key couldn't be kept, which would leave the provider without it.
    @State private var saveFailure: String?

    private enum TestState: Equatable { case idle, testing, worked, failed(String) }

    var body: some View {
        SecureField("API key", text: $key, prompt: Text("Paste your \(provider.name) key"))
            .onAppear { key = Keychain.string(for: provider.keychainAccount) ?? "" }
            .onChange(of: key) { _, newKey in
                do {
                    try Keychain.set(newKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keychainAccount)
                    saveFailure = nil
                } catch {
                    saveFailure = "The key couldn't be saved to the Keychain: \(error.localizedDescription)"
                }
                test = .idle
            }
        if let saveFailure {
            Text(saveFailure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 10) {
            if let page = provider.keyPage {
                Link(provider.keyIsFree ? "Get a free key" : "Get a key", destination: page)
            }
            Spacer()
            switch test {
            case .idle: EmptyView()
            case .testing: ProgressView().controlSize(.small)
            case .worked: Label("It works", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let reason): Text(reason).foregroundStyle(.red).lineLimit(2)
            }
            Button("Test Key", action: runTest).disabled(key.isEmpty || test == .testing)
        }
    }

    /// Asks for a forecast for the location set, or for London when there's none yet.
    private func runTest() {
        test = .testing
        Task {
            let place = (try? await WeatherService.shared.place(for: location))
                ?? WeatherPlace(name: "London", coordinate: Coordinate(latitude: 51.51, longitude: -0.13), timeZoneID: "Europe/London")
            do throws(WeatherError) {
                _ = try await provider.source.report(at: place.coordinate, key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     timeZone: place.timeZone, using: URLSessionWeatherHTTP.shared)
                test = .worked
            } catch {
                let reason = switch error {
                case .badKey: "\(provider.name) turned the key down."
                case .rateLimited: "The key works, but it's used up for now."
                case .offline: "No connection."
                default: "\(provider.name) didn't answer as expected."
                }
                test = .failed(reason)
            }
        }
    }
}

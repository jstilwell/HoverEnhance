import SwiftUI

/// Settings → macOS: popups for the system's own menu bar items.
struct MacOSSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.networkEnabled) {
                    Text("Show network details")
                    Text("When the cursor rests on the Wi-Fi item in the menu bar")
                }
                Toggle(isOn: $settings.networkLooksUpPublicAddress) {
                    Text("Look up the public IP address")
                    Text("Asks addr.fyi, which sees only the address it answers with. Asked again when the network changes.")
                }
                .disabled(!settings.networkEnabled)
            } header: {
                Text("Network")
            } footer: {
                Footnote("Everything else is read from this Mac. macOS shows the Wi-Fi network's name only to apps allowed Location Services.")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: settingsHeight)
    }
}

import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private let settingsWidth: CGFloat = 540

/// Section footers in grouped forms trail-align by default; settings text reads better leading.
private struct Footnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show previews", isOn: $settings.previewsEnabled)
                LaunchAtLoginToggle()
            }
            Section {
                Picker("Previews appear", selection: $settings.activation) {
                    ForEach(Activation.allCases) { Text($0.label).tag($0) }
                }
                Picker("Key", selection: $settings.activationKey) {
                    ForEach(ModifierKey.allCases) { Text($0.label).tag($0) }
                }
                .disabled(settings.activation == .always)
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: 0...600, step: 25)
                        Text("\(Int(settings.hoverDelay)) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
            } header: {
                Text("Activation")
            } footer: {
                Footnote("How long the cursor rests on something before its preview starts. Shorter feels quicker; longer avoids previews while you sweep across a page.")
            }
            Section {
                ExcludedAppsEditor(apps: $settings.excludedApps)
            } header: {
                Text("Excluded apps")
            } footer: {
                Footnote("No previews appear while the cursor is over these apps.")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 540)
    }
}

/// Registers the app as a login item. The system keeps this state, not UserDefaults.
private struct LaunchAtLoginToggle: View {
    @State private var isOn = SMAppService.mainApp.status == .enabled
    @State private var note: String?

    var body: some View {
        Toggle("Open at login", isOn: Binding(get: { isOn }, set: update))
        if let note {
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func update(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            note = nil
        } catch {
            note = error.localizedDescription
        }
        let status = SMAppService.mainApp.status
        isOn = status == .enabled
        if status == .requiresApproval {
            note = "Allow HoverEnhance in System Settings → General → Login Items."
        }
    }
}

private struct ExcludedAppsEditor: View {
    @Binding var apps: [ExcludedApp]

    var body: some View {
        if apps.isEmpty {
            Text("None").foregroundStyle(.secondary)
        }
        ForEach(apps) { app in
            HStack {
                Image(nsImage: Self.icon(for: app.bundleID)).resizable().frame(width: 18, height: 18)
                Text(app.name)
                Spacer()
                Button {
                    apps.removeAll { $0 == app }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(app.name)")
            }
        }
        Menu("Add App") {
            ForEach(runningApps) { app in
                Button(app.name) { apps.append(app) }
            }
            if !runningApps.isEmpty { Divider() }
            Button("Choose…", action: choose)
        }
        .fixedSize()
    }

    /// Open apps that aren't excluded yet.
    private var runningApps: [ExcludedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let id = app.bundleIdentifier, !apps.contains(where: { $0.bundleID == id }) else { return nil }
                return ExcludedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              !apps.contains(where: { $0.bundleID == id }) else { return }
        apps.append(ExcludedApp(bundleID: id, name: FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            .replacingOccurrences(of: ".app", with: "")))
    }

    private static func icon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}

// MARK: - Previews

struct PreviewsSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Show") {
                Toggle(isOn: $settings.showImages) {
                    Text("Images")
                    Text("Full-size versions of thumbnails and links to images")
                }
                Toggle(isOn: $settings.showAlbums) {
                    Text("Albums")
                    Text("Every item of galleries and multi-photo posts; scroll to step through. Off shows the first.")
                }
                Toggle(isOn: $settings.showVideos) {
                    Text("Videos")
                    Text("Streamable, Reddit, X, Bluesky, Instagram, and links to video files")
                }
                Toggle(isOn: $settings.showEmbeds) {
                    Text("Embedded players")
                    Text("YouTube, Vimeo, TikTok, and Twitch, in each site's own player")
                }
                Toggle(isOn: $settings.showCards) {
                    Text("Creator cards")
                    Text("On YouTube, a video title or channel name shows its creator. Thumbnails are left to YouTube.")
                }
            }
            Section {
                LabeledContent("Largest preview") {
                    HStack {
                        Slider(value: $settings.maximumSize, in: 0.3...1, step: 0.05)
                        Text("\(Int((settings.maximumSize * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Enlarge images by at least") {
                    HStack {
                        Slider(value: $settings.minimumEnlargement, in: 1...3, step: 0.1)
                        Text(String(format: "%.1f×", settings.minimumEnlargement)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Size")
            } footer: {
                Footnote("Previews take up to this share of the space beside the cursor. An image isn't previewed unless it would appear at least this much bigger than it does on the page.")
            }
            Section {
                Toggle("Show the notch under the cursor", isOn: $settings.showsNotch)
                Picker("Scroll wheel on images", selection: $settings.imageScroll) {
                    ForEach(ImageScroll.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Notch and scroll wheel")
            } footer: {
                Footnote("Moving off the notch any way but onto the preview closes the preview, even with the notch hidden. With the cursor on the notch or the preview, the scroll wheel acts on the preview instead of the page: albums step through their items, and single images do what's set here.")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 780)
    }
}

// MARK: - Video

struct VideoSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Videos start", selection: $settings.videoSound) {
                    ForEach(VideoSound.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $settings.videoVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Sound")
            } footer: {
                Footnote("“As last set” keeps whatever you last chose with a video's mute button. Embedded players have their own volume.")
            }
            Section {
                Picker("Scroll wheel", selection: $settings.videoScroll) {
                    ForEach(VideoScroll.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Loop videos", isOn: $settings.loopVideos)
                Toggle(isOn: $settings.resumeVideos) {
                    Text("Resume where you left off")
                    Text("Reopening a video picks up where its preview closed")
                }
            } header: {
                Text("Playback")
            } footer: {
                Footnote("The scroll wheel works with the cursor on the notch or the video. Embedded players handle scrolling themselves.")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 430)
    }
}

// MARK: - Sites

struct SitesSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(MediaSite.allCases) { site in
                    Toggle(isOn: Binding(
                        get: { !settings.disabledSites.contains(site) },
                        set: { on in
                            if on { settings.disabledSites.remove(site) } else { settings.disabledSites.insert(site) }
                        }
                    )) {
                        Text(site.name)
                        Text(site.detail)
                    }
                }
            } footer: {
                Footnote("Images and video links on other sites follow the Previews settings.")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 730)
    }
}

// MARK: - Finder

struct FinderSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.finderCards) {
                    Text("Show file cards")
                    Text("Resting on a file or folder in Finder or on the desktop shows a card about it")
                }
                LabeledContent("Show after") {
                    HStack {
                        // Never sooner than the hover delay, which the cursor has already waited out.
                        Slider(value: $settings.finderDelay, in: settings.hoverDelay...max(settings.hoverDelay, 2000), step: 50)
                        Text("\(Int(max(settings.finderDelay, settings.hoverDelay))) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
                .disabled(!settings.finderCards)
            } footer: {
                Footnote("Cards wait longer than other previews, so sweeping across a folder doesn't flash them. Clicking a file or moving off it closes its card.")
            }
            Section {
                Toggle(isOn: $settings.finderShowsPath) {
                    Text("Path")
                    Text("Click it to copy it")
                }
                Picker("Copy path as", selection: $settings.finderPathStyle) {
                    ForEach(PathStyle.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.finderShowsPath)
                LabeledContent("Example") {
                    Text(settings.finderPathStyle.format(NSHomeDirectory() + "/Downloads/Project Notes (v2).txt"))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Show")
            }
            .disabled(!settings.finderCards)
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 420)
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var cacheBytes = Maintenance.imageCacheBytes
    @State private var websiteDataCleared = false

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack {
                        Label(accessibilityGranted ? "Allowed" : "Not allowed",
                              systemImage: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        if !accessibilityGranted {
                            Button("Open System Settings…") {
                                AccessibilityPermission.request()
                                AccessibilityPermission.openSettings()
                            }
                        }
                    }
                }
            }
            Section {
                LabeledContent("Image cache") {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)).monospacedDigit()
                        Button("Clear") {
                            Maintenance.clearImageCache()
                            cacheBytes = Maintenance.imageCacheBytes
                        }
                    }
                }
                LabeledContent("Website data") {
                    Button(websiteDataCleared ? "Cleared" : "Clear") {
                        Task {
                            await Maintenance.clearWebsiteData()
                            websiteDataCleared = true
                        }
                    }
                    .disabled(websiteDataCleared)
                }
            } header: {
                Text("Storage")
            } footer: {
                Footnote("Website data is cookies from pages HoverEnhance loads, such as the one Reddit sets after its browser check.")
            }
            Section("Troubleshooting") {
                Toggle(isOn: $settings.showsInspector) {
                    Text("Show inspector")
                    Text("A panel in the corner listing what's under the cursor: role, labels, and URLs")
                }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 470)
        .onAppear {
            accessibilityGranted = AccessibilityPermission.isGranted
            cacheBytes = Maintenance.imageCacheBytes
        }
    }
}

// MARK: - Accounts

struct AccountsSettingsView: View {
    @Bindable var account: YouTubeAccount
    @State private var showsSteps = false

    var body: some View {
        Form {
            Section {
                if account.status == .signedIn {
                    LabeledContent("Signed in as") {
                        HStack {
                            Text(account.accountName ?? "Your YouTube account")
                            Button("Sign Out") { Task { await account.signOut() } }
                        }
                    }
                    accessRow
                } else {
                    TextField("Client ID", text: $account.clientID, prompt: Text("…apps.googleusercontent.com"))
                    SecureField("Client secret", text: $account.clientSecret, prompt: Text("GOCSPX-…"))
                    HStack {
                        Spacer()
                        Button(account.status == .signingIn ? "Waiting for the Browser…" : "Sign In with Google…") {
                            Task { await account.signIn() }
                        }
                        .disabled(!account.canSignIn)
                    }
                }
                if let error = account.lastError {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("YouTube")
            } footer: {
                Footnote("Lets creator cards show whether you're subscribed, and subscribe or unsubscribe. Sign-in goes through your own Google Cloud OAuth client; its secret and your sign-in are kept in the Keychain.")
            }
            Section {
                DisclosureGroup("Setting up a Google Cloud client", isExpanded: Binding(
                    get: { showsSteps || account.status != .signedIn }, set: { showsSteps = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. In Google Cloud Console, create a project. In that same project, open APIs & Services → Library, find **YouTube Data API v3**, and click **Enable**.")
                        Text("2. Under **Google Auth Platform**, fill in Branding (an app name and your email). In Audience, choose External and **Publish app**, so sign-in doesn't expire every week.")
                        Text("3. Under **Clients**, create a client of type **Desktop app**, then copy its ID and secret here.")
                        Text("4. Sign in. Google warns that the app isn't verified, since it's your own: choose Advanced, then Go to the app.")
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    Link("Open Google Cloud Console", destination: YouTubeAPI.consoleURL)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: 560)
        .task { await account.checkAccess() }
    }

    /// Whether signed-in calls work, with the fix when they don't.
    @ViewBuilder
    private var accessRow: some View {
        switch account.access {
        case .unknown, .checking:
            LabeledContent("YouTube access") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(.secondary)
                }
            }
        case .working:
            LabeledContent("YouTube access") {
                Label("Working", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failing(let message, let fix):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let fix {
                        Button("Turn On YouTube API…") { NSWorkspace.shared.open(fix) }
                    }
                    Button("Check Again") { Task { await account.checkAccess() } }
                }
                if fix != nil {
                    Text("After turning it on, it can take a few minutes before YouTube answers.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

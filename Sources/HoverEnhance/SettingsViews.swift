import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

let settingsWidth: CGFloat = 540
/// Every tab is the same size, so the window doesn't jump between tabs, and short enough for a
/// 1280 × 800 screen; longer tabs scroll.
let settingsHeight: CGFloat = 600

/// Section footers in grouped forms trail-align by default; settings text reads better leading.
struct Footnote: View {
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
    @State private var confirmsOtherApps = false

    var body: some View {
        Form {
            Section {
                Toggle("Show previews", isOn: $settings.previewsEnabled)
                LabeledContent {
                    ShortcutRecorder(shortcut: $settings.pauseShortcut)
                } label: {
                    Text("Shortcut")
                    Text("Shows or hides previews from any app")
                }
                LaunchAtLoginToggle()
            }
            Section {
                Picker("Previews appear", selection: $settings.activation) {
                    ForEach(Activation.allCases) { Text($0.label).tag($0) }
                }
                Picker("Key", selection: $settings.activationKey) {
                    ForEach(ModifierKey.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.usesActivationKey)
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: AppSettings.shortestHoverDelay...600, step: 25)
                        Text("\(Int(settings.hoverDelay)) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
            } header: {
                Text("Activation")
            } footer: {
                Footnote("How long the cursor rests on something before its preview starts. Shorter feels quicker; longer avoids previews while you sweep across a page.")
            }
            Section {
                Toggle(isOn: Binding(
                    get: { settings.previewsInOtherApps },
                    // Turning it on goes through the safety options first.
                    set: { on in if on { confirmsOtherApps = true } else { settings.previewsInOtherApps = false } }
                )) {
                    Text("Preview links in other apps")
                    Text("Apps that aren't browsers, such as Messages, Slack, or Notes")
                }
                if settings.previewsInOtherApps {
                    OtherAppsOptions(skipsEmail: $settings.otherAppsSkipEmail, knownSitesOnly: $settings.otherAppsKnownSitesOnly,
                                     needsKey: $settings.otherAppsNeedKey, settings: settings)
                }
            } header: {
                Text("Other apps")
            } footer: {
                Footnote(OtherAppsOptions.explanation + " Finder's file cards don't use the network and always appear.")
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
        .frame(width: settingsWidth, height: settingsHeight)
        .sheet(isPresented: $confirmsOtherApps) {
            OtherAppsSheet(settings: settings)
        }
    }
}

/// The safety options for previews outside browsers, in Settings and in the sheet that turns them on.
private struct OtherAppsOptions: View {
    @Binding var skipsEmail: Bool
    @Binding var knownSitesOnly: Bool
    @Binding var needsKey: Bool
    let settings: AppSettings

    static let explanation = "In a browser, a preview loads only what the page could load itself. In other apps it can give something away: an email can carry a link that tells its sender you read the message, and where you are."

    var body: some View {
        Toggle(isOn: $skipsEmail) {
            Text("Skip email apps")
            Text("Mail, Outlook, and other apps that handle email links")
        }
        Toggle(isOn: $knownSitesOnly) {
            Text("Only links to known sites")
            Text("Reddit, X, YouTube, and the others under Sites, but not images from anywhere, which is how tracking pixels work")
        }
        Toggle(isOn: $needsKey) {
            Text("Only while holding \(settings.activationKey.label)")
            Text(settings.activation == .unlessHoldingKey
                 ? "Not available while previews appear except while holding a key"
                 : "Nothing loads until you ask for it. The key is set under Activation.")
        }
        .disabled(settings.activation == .unlessHoldingKey)
    }
}

/// Asks how careful to be before previews start loading links outside browsers.
struct OtherAppsSheet: View {
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var skipsEmail: Bool
    @State private var knownSitesOnly: Bool
    @State private var needsKey: Bool

    init(settings: AppSettings) {
        self.settings = settings
        _skipsEmail = State(initialValue: settings.otherAppsSkipEmail)
        _knownSitesOnly = State(initialValue: settings.otherAppsKnownSitesOnly)
        _needsKey = State(initialValue: settings.otherAppsNeedKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview links in other apps?").font(.headline)
                    Text("To preview a link, HoverEnhance loads what it points to, from your Mac. " + OtherAppsOptions.explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding([.horizontal, .top], 20)
            Form {
                OtherAppsOptions(skipsEmail: $skipsEmail, knownSitesOnly: $knownSitesOnly, needsKey: $needsKey, settings: settings)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Turn On") {
                    settings.otherAppsSkipEmail = skipsEmail
                    settings.otherAppsKnownSitesOnly = knownSitesOnly
                    settings.otherAppsNeedKey = needsKey
                    settings.previewsInOtherApps = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Registers the app as a login item. The system keeps this state, not UserDefaults.
/// Records a key combination: click, then press it. Esc stops without changing it.
private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        HStack(spacing: 6) {
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.secondary)
            }
            Button(monitor != nil ? "Press a shortcut…" : shortcut?.label ?? "Record Shortcut") {
                if monitor != nil { stop() } else { start() }
            }
            .accessibilityHint(monitor != nil ? "Press the keys, or Escape to stop" : "Click, then press the keys")
            if let shortcut, monitor == nil {
                Button {
                    self.shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(shortcut.label)")
                .accessibilityLabel("Remove the shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        problem = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 {
                    stop()
                } else if let recorded = Shortcut(event: event) {
                    // The current shortcut is held by this app, so it's the one combination not to try.
                    if recorded == shortcut || GlobalShortcut.isAvailable(recorded) {
                        shortcut = recorded
                        stop()
                    } else {
                        problem = "\(recorded.label) is taken"
                    }
                } else {
                    problem = "Use two of ⌘ ⌥ ⌃ ⇧"
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var isOn = SMAppService.mainApp.status == .enabled
    @State private var note: String?

    var body: some View {
        Toggle("Open at login", isOn: Binding(get: { isOn }, set: update))
            // It can be changed in System Settings too, while this window stays open.
            .onAppear { isOn = SMAppService.mainApp.status == .enabled }
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
                .accessibilityLabel("Remove \(app.name)")
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

    static let imageLimits = [5, 10, 25, 50, 100]

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
                    Text("Cards")
                    Text("Links to Wikipedia articles and GitHub repositories, issues, and pull requests. On YouTube, a video title or channel name shows its creator; thumbnails are left to YouTube.")
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
                Picker("Largest image to download", selection: $settings.largestImageMegabytes) {
                    ForEach(PreviewsSettingsView.imageLimits, id: \.self) { Text("\($0) MB").tag($0) }
                }
            } header: {
                Text("Size")
            } footer: {
                Footnote("Previews take up to this share of the space beside the cursor. An image isn't previewed unless it would appear at least this much bigger than it does on the page. A larger image than the download limit shows its size instead, with Load Anyway.")
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
        .frame(width: settingsWidth, height: settingsHeight)
    }
}

// MARK: - Video

struct VideoSettingsView: View {
    @Bindable var settings: AppSettings

    static let scrubSteps = [1, 2, 5, 10]

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
                Picker("Scrolling on the video", selection: $settings.videoScroll) {
                    ForEach(VideoScroll.allCases) { Text($0.label).tag($0) }
                }
                Picker("Scrolling on the notch", selection: $settings.notchVideoScroll) {
                    ForEach(VideoScroll.allCases) { Text($0.label).tag($0) }
                }
                Picker("Each scroll step moves it", selection: $settings.videoScrubSeconds) {
                    ForEach(VideoSettingsView.scrubSteps, id: \.self) { Text($0 == 1 ? "1 second" : "\($0) seconds").tag($0) }
                }
                .disabled(settings.videoScroll != .scrub && settings.notchVideoScroll != .scrub)
                Toggle("Loop videos", isOn: $settings.loopVideos)
                Toggle(isOn: $settings.resumeVideos) {
                    Text("Resume where you left off")
                    Text("Reopening a video picks up where its preview closed")
                }
            } header: {
                Text("Playback")
            } footer: {
                Footnote("The notch is the tab under the cursor that joins it to the preview; during a video, the volume shows beside it, and scrolling there counts as the notch. Embedded players handle scrolling themselves.")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: settingsHeight)
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
            Section {
                Toggle(isOn: $settings.skipsWebmail) {
                    Text("Skip webmail")
                    Text("Gmail, Outlook, iCloud Mail, Yahoo, Proton, and others: a link in an email can tell its sender you read it, and where you are")
                }
                SkippedWebsitesEditor(domains: $settings.skippedWebsites)
            } header: {
                Text("Skipped websites")
            } footer: {
                Footnote("No previews appear on these websites' pages, or their subdomains'. The menu bar menu can skip the one you're on.")
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: settingsHeight)
    }
}

/// The websites previews skip, with a field to add another.
private struct SkippedWebsitesEditor: View {
    @Binding var domains: [String]
    @State private var entry = ""

    var body: some View {
        if domains.isEmpty {
            Text("None").foregroundStyle(.secondary)
        }
        ForEach(domains, id: \.self) { domain in
            HStack {
                Text(domain)
                Spacer()
                Button {
                    domains.removeAll { $0 == domain }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(domain)")
                .accessibilityLabel("Remove \(domain)")
            }
        }
        HStack {
            TextField("Website", text: $entry, prompt: Text("Website to skip, such as example.com"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button("Add", action: add).disabled(newDomain == nil)
        }
    }

    private var newDomain: String? {
        SkippedWebsites.domain(from: entry).flatMap { domains.contains($0) ? nil : $0 }
    }

    private func add() {
        guard let domain = newDomain else { return }
        domains.append(domain)
        entry = ""
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
                    Text("Resting on a file or folder in Finder shows a card about it")
                }
                Group {
                    LabeledContent("Show after") {
                        HStack {
                            // Never sooner than the hover delay, which the cursor has already waited out.
                            Slider(value: $settings.finderDelay, in: settings.hoverDelay...max(settings.hoverDelay, 2000), step: 50)
                            Text("\(Int(max(settings.finderDelay, settings.hoverDelay))) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                        }
                    }
                    Toggle(isOn: $settings.finderMediaPreviews) {
                        Text("Large previews of images, videos, and audio")
                        Text("The file itself, large, with its details beside or below. Videos play; audio shows its artwork.")
                    }
                    Toggle(isOn: $settings.finderAutoplayAudio) {
                        Text("Play audio right away")
                        Text("Otherwise its play button starts it")
                    }
                    .disabled(!settings.finderMediaPreviews)
                    Toggle("On the desktop", isOn: $settings.finderOnDesktop)
                    Toggle(isOn: $settings.finderForFolders) {
                        Text("For folders")
                        Text("Off, cards show only for files, and for apps and other packages")
                    }
                }
                .disabled(!settings.finderCards)
            } header: {
                Text("When")
            } footer: {
                Footnote("Cards wait longer than other previews, so sweeping across a folder doesn't flash them. Clicking a file or moving off it closes its card.")
            }
            Group {
                Section("Behavior") {
                    Toggle(isOn: $settings.finderClosesOnKeyPress) {
                        Text("Close when a key is pressed")
                        Text("Space for Quick Look, Return to rename, or typing to find a file")
                    }
                    Toggle(isOn: $settings.finderCopiesDetails) {
                        Text("Click a detail to copy it")
                        Text("Dates are copied in full; the path can always be copied")
                    }
                }
                ForEach(FileCardField.Group.allCases) { group in
                    Section {
                        ForEach(group.fields) { field in
                            Toggle(isOn: shows(field)) {
                                Text(field.name)
                                if let detail = field.detail { Text(detail) }
                            }
                        }
                        extras(for: group)
                    } header: {
                        Text(group.title)
                    } footer: {
                        if let note = footnote(for: group) { Footnote(note) }
                    }
                }
                Section {
                    HStack {
                        Spacer()
                        Button("Restore Defaults") { settings.restoreFinderDefaults() }
                    }
                }
            }
            .disabled(!settings.finderCards)
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: settingsHeight)
    }

    private func shows(_ field: FileCardField) -> Binding<Bool> {
        Binding(
            get: { !settings.finderHiddenFields.contains(field) },
            set: { on in
                if on { settings.finderHiddenFields.remove(field) } else { settings.finderHiddenFields.insert(field) }
            }
        )
    }

    /// Settings that belong with a group's details.
    @ViewBuilder
    private func extras(for group: FileCardField.Group) -> some View {
        switch group {
        case .path:
            Group {
                Picker("Copy path as", selection: $settings.finderPathStyle) {
                    ForEach(PathStyle.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Example") {
                    Text(settings.finderPathStyle.format(NSHomeDirectory() + "/Downloads/Project Notes (v2).txt"))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .disabled(settings.finderHiddenFields.contains(.path))
        case .inUse:
            Toggle(isOn: $settings.finderOffersQuit) {
                Text("Offer to quit them")
                Text("Quit takes a second click to confirm. If something doesn't quit, Force Quit appears.")
            }
            .disabled(settings.finderHiddenFields.contains(.users))
        default:
            EmptyView()
        }
    }

    private func footnote(for group: FileCardField.Group) -> String? {
        switch group {
        case .card:
            "Details come from Spotlight and Finder's own records where they can. Thumbnails, the tags in audio and video files, and files Spotlight hasn't indexed are read directly, so macOS may ask once before HoverEnhance reads files in Desktop, Documents, or Downloads."
        case .inUse:
            "Quitting an app is like pressing ⌘Q in it, so it can still ask to save; other processes get the polite signal the kill command sends. Only your own processes are listed."
        default:
            nil
        }
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    @Bindable var settings: AppSettings
    let access: AccessibilityWatcher
    @Bindable var updates: Updates

    /// "0.2.0".
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    /// "0.2.0", or "0.2.0 (14)" when the build number differs.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String
        let build = (info["CFBundleVersion"] as? String).flatMap { $0 == short ? nil : "(\($0))" }
        return [short, build].compactMap { $0 }.joined(separator: " ").nilIfEmpty ?? "–"
    }
    @State private var cacheBytes = Maintenance.imageCacheBytes
    @State private var websiteDataCleared = false

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack {
                        Label(access.isGranted ? "Allowed" : "Not allowed",
                              systemImage: access.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(access.isGranted ? .green : .orange)
                        if !access.isGranted {
                            Button("Show Setup Guide…") {
                                NotificationCenter.default.post(name: .showAccessibilityGuide, object: nil)
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
                            // The files are removed in the background, so the size drops a moment later.
                            Task {
                                for _ in 0..<20 {
                                    cacheBytes = Maintenance.imageCacheBytes
                                    if cacheBytes == 0 { break }
                                    try? await Task.sleep(for: .milliseconds(100))
                                }
                            }
                        }
                    }
                }
                LabeledContent("Website data") {
                    Button(websiteDataCleared ? "Cleared" : "Clear") {
                        Task {
                            await Maintenance.clearWebsiteData()
                            websiteDataCleared = true
                            // Sites set cookies again as they're used, so it can be cleared again.
                            try? await Task.sleep(for: .seconds(2))
                            websiteDataCleared = false
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
            Section {
                if updates.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                    HStack {
                        if let version = updates.waitingVersion {
                            Text("Version \(version) is ready to install.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(updates.waitingVersion == nil ? "Check Now" : "Install…") { updates.checkForUpdates() }
                    }
                } else {
                    Text("This copy was built from source and doesn't update itself.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                if updates.isAvailable {
                    Footnote(Updates.checksOnlyWhenAsked
                             ? "This is a debug build, so it checks only when you click Check Now."
                             : "Updates are signed and checked before they're installed. Installing one restarts HoverEnhance.")
                }
            }
            Section("About") {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Website") {
                    Link("hoverenhance.com", destination: AboutView.website)
                }
                LabeledContent("Source") {
                    Link("github.com/jstilwell/HoverEnhance", destination: AboutView.repository)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth, height: settingsHeight)
        .onAppear {
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
        .frame(width: settingsWidth, height: settingsHeight)
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

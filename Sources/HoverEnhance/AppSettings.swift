import AppKit
import Observation

/// When previews appear, relative to a modifier key.
enum Activation: String, CaseIterable, Identifiable, Sendable {
    case always, whileHoldingKey, unlessHoldingKey

    var id: Self { self }

    var label: String {
        switch self {
        case .always: "Always"
        case .whileHoldingKey: "Only while holding a key"
        case .unlessHoldingKey: "Except while holding a key"
        }
    }
}

enum ModifierKey: String, CaseIterable, Identifiable, Sendable {
    case option, control, command, shift

    var id: Self { self }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .option: .option
        case .control: .control
        case .command: .command
        case .shift: .shift
        }
    }

    var label: String {
        switch self {
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .command: "⌘ Command"
        case .shift: "⇧ Shift"
        }
    }
}

/// Whether a video starts with sound.
enum VideoSound: String, CaseIterable, Identifiable, Sendable {
    case remember, muted, unmuted

    var id: Self { self }

    var label: String {
        switch self {
        case .remember: "As last set"
        case .muted: "Muted"
        case .unmuted: "With sound"
        }
    }
}

/// What the scroll wheel does to a single image, with the cursor on the notch or the preview.
enum ImageScroll: String, CaseIterable, Identifiable, Sendable {
    case zoom, page

    var id: Self { self }

    var label: String {
        switch self {
        case .zoom: "Zoom in and out"
        case .page: "Scroll the page"
        }
    }
}

/// What the scroll wheel does to a video, with the cursor on the notch or the video.
enum VideoScroll: String, CaseIterable, Identifiable, Sendable {
    case scrub, volume

    var id: Self { self }

    var label: String {
        switch self {
        case .scrub: "Move through the video"
        case .volume: "Change the volume"
        }
    }
}

/// How a file card writes a path, which is also how it's copied.
enum PathStyle: String, CaseIterable, Identifiable, Sendable {
    case full, tilde, quoted

    var id: Self { self }

    var label: String {
        switch self {
        case .full: "Full path"
        case .tilde: "Starting with ~"
        case .quoted: "Quoted for the shell"
        }
    }
}

/// Parts of the weather popup that can be turned off.
enum WeatherSection: String, CaseIterable, Identifiable, Sendable {
    case hourly, daily, details, airQuality, pollen, alerts

    var id: Self { self }

    var name: String {
        switch self {
        case .hourly: "Hourly forecast"
        case .daily: "Daily forecast"
        case .details: "Wind, humidity, pressure, UV, and more"
        case .airQuality: "Air quality"
        case .pollen: "Pollen"
        case .alerts: "Weather alerts"
        }
    }
}

struct ExcludedApp: Codable, Hashable, Identifiable, Sendable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

/// User settings, kept in UserDefaults. Code reads them where they're used, so changes apply at once.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let previewsEnabled = "previewsEnabled"
        static let activation = "activation"
        static let activationKey = "activationKey"
        static let hoverDelay = "hoverDelay"
        static let excludedApps = "excludedApps"
        static let skippedWebsites = "skippedWebsites"
        static let skipWebmail = "skipWebmail"
        static let pauseShortcut = "pauseShortcut"
        static let previewsInOtherApps = "previewsInOtherApps"
        static let otherAppsSkipEmail = "otherAppsSkipEmail"
        static let otherAppsKnownSitesOnly = "otherAppsKnownSitesOnly"
        static let otherAppsNeedKey = "otherAppsNeedKey"
        static let showImages = "showImages"
        static let showAlbums = "showAlbums"
        static let showVideos = "showVideos"
        static let showEmbeds = "showEmbeds"
        static let showCards = "showCards"
        static let disabledSites = "disabledSites"
        static let minimumEnlargement = "minimumEnlargement"
        static let maximumSize = "maximumSize"
        static let largestImageMegabytes = "largestImageMegabytes"
        static let showsNotch = "showsNotch"
        static let imageScroll = "imageScroll"
        static let videoScroll = "videoScroll"
        static let notchVideoScroll = "notchVideoScroll"
        static let videoScrubSeconds = "videoScrubSeconds"
        static let videoSound = "videoSound"
        static let videoMuted = "videoMuted"
        static let videoVolume = "videoVolume"
        static let loopVideos = "loopVideos"
        static let resumeVideos = "resumeVideos"
        static let showsInspector = "showsInspector"
        static let finderCards = "finderCards"
        static let finderDelay = "finderDelay"
        static let finderPathStyle = "finderPathStyle"
        static let finderHiddenFields = "finderHiddenFields"
        static let finderOnDesktop = "finderOnDesktop"
        static let finderForFolders = "finderForFolders"
        static let finderClosesOnKeyPress = "finderClosesOnKeyPress"
        static let finderCopiesDetails = "finderCopiesDetails"
        static let finderOffersQuit = "finderOffersQuit"
        static let finderMediaPreviews = "finderMediaPreviews"
        static let finderAutoplayAudio = "finderAutoplayAudio"
        static let weatherEnabled = "weatherEnabled"
        static let weatherProvider = "weatherProvider"
        static let weatherLocation = "weatherLocation"
        static let weatherUnits = "weatherUnits"
        static let weatherHiddenSections = "weatherHiddenSections"
        static let weatherUsesNWSAlerts = "weatherUsesNWSAlerts"
        static let networkEnabled = "networkEnabled"
        static let networkLooksUpPublicAddress = "networkLooksUpPublicAddress"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // General
    var previewsEnabled: Bool { didSet { defaults.set(previewsEnabled, forKey: Key.previewsEnabled) } }
    var activation: Activation { didSet { defaults.set(activation.rawValue, forKey: Key.activation) } }
    var activationKey: ModifierKey { didSet { defaults.set(activationKey.rawValue, forKey: Key.activationKey) } }
    /// Milliseconds the cursor rests before a preview starts. At least `shortestHoverDelay`: shorter, and
    /// the cursor would be looked under between every two moves it makes.
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    static let shortestHoverDelay = 50.0
    var excludedApps: [ExcludedApp] {
        didSet { defaults.set(try? JSONEncoder().encode(excludedApps), forKey: Key.excludedApps) }
    }
    /// Domains, such as "bank.example", on whose pages (and their subdomains') no previews appear.
    var skippedWebsites: [String] { didSet { defaults.set(skippedWebsites, forKey: Key.skippedWebsites) } }
    /// No previews on webmail's pages; see `Webmail`.
    var skipsWebmail: Bool { didSet { defaults.set(skipsWebmail, forKey: Key.skipWebmail) } }
    /// Shows or hides previews from any app.
    var pauseShortcut: Shortcut? {
        didSet { defaults.set(pauseShortcut.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.pauseShortcut) }
    }
    /// Previews that load from the network in apps other than browsers; see `OtherAppsPolicy`.
    var previewsInOtherApps: Bool { didSet { defaults.set(previewsInOtherApps, forKey: Key.previewsInOtherApps) } }
    var otherAppsSkipEmail: Bool { didSet { defaults.set(otherAppsSkipEmail, forKey: Key.otherAppsSkipEmail) } }
    var otherAppsKnownSitesOnly: Bool { didSet { defaults.set(otherAppsKnownSitesOnly, forKey: Key.otherAppsKnownSitesOnly) } }
    var otherAppsNeedKey: Bool { didSet { defaults.set(otherAppsNeedKey, forKey: Key.otherAppsNeedKey) } }

    // Previews
    var showImages: Bool { didSet { defaults.set(showImages, forKey: Key.showImages) } }
    var showAlbums: Bool { didSet { defaults.set(showAlbums, forKey: Key.showAlbums) } }
    var showVideos: Bool { didSet { defaults.set(showVideos, forKey: Key.showVideos) } }
    var showEmbeds: Bool { didSet { defaults.set(showEmbeds, forKey: Key.showEmbeds) } }
    var showCards: Bool { didSet { defaults.set(showCards, forKey: Key.showCards) } }
    var disabledSites: Set<MediaSite> {
        didSet { defaults.set(disabledSites.map(\.rawValue).sorted(), forKey: Key.disabledSites) }
    }
    /// A lone image is previewed only if it would appear at least this many times larger.
    var minimumEnlargement: Double { didSet { defaults.set(minimumEnlargement, forKey: Key.minimumEnlargement) } }
    /// The largest preview, as a fraction of the room beside the cursor.
    var maximumSize: Double { didSet { defaults.set(maximumSize, forKey: Key.maximumSize) } }
    /// Images larger than this aren't downloaded unless asked for.
    var largestImageMegabytes: Int { didSet { defaults.set(largestImageMegabytes, forKey: Key.largestImageMegabytes) } }
    var largestImageBytes: Int64 { Int64(largestImageMegabytes) * 1_000_000 }
    var showsNotch: Bool { didSet { defaults.set(showsNotch, forKey: Key.showsNotch) } }
    var imageScroll: ImageScroll { didSet { defaults.set(imageScroll.rawValue, forKey: Key.imageScroll) } }

    // Video
    var videoSound: VideoSound { didSet { defaults.set(videoSound.rawValue, forKey: Key.videoSound) } }
    /// The player's last mute state, used when `videoSound` is `.remember`.
    var videoMuted: Bool { didSet { defaults.set(videoMuted, forKey: Key.videoMuted) } }
    var videoVolume: Double { didSet { defaults.set(videoVolume, forKey: Key.videoVolume) } }
    var loopVideos: Bool { didSet { defaults.set(loopVideos, forKey: Key.loopVideos) } }
    var resumeVideos: Bool { didSet { defaults.set(resumeVideos, forKey: Key.resumeVideos) } }
    /// What scrolling on a video does.
    var videoScroll: VideoScroll { didSet { defaults.set(videoScroll.rawValue, forKey: Key.videoScroll) } }
    /// What scrolling on the notch, or the volume rocker beside it, does to a video.
    var notchVideoScroll: VideoScroll { didSet { defaults.set(notchVideoScroll.rawValue, forKey: Key.notchVideoScroll) } }
    /// Seconds a scroll step moves a video.
    var videoScrubSeconds: Int { didSet { defaults.set(videoScrubSeconds, forKey: Key.videoScrubSeconds) } }

    // Finder
    var finderCards: Bool { didSet { defaults.set(finderCards, forKey: Key.finderCards) } }
    /// Milliseconds the cursor rests on a file before its card appears; never less than `hoverDelay`.
    var finderDelay: Double { didSet { defaults.set(finderDelay, forKey: Key.finderDelay) } }
    var finderPathStyle: PathStyle { didSet { defaults.set(finderPathStyle.rawValue, forKey: Key.finderPathStyle) } }
    /// Details the card leaves out.
    var finderHiddenFields: Set<FileCardField> {
        didSet { defaults.set(finderHiddenFields.map(\.rawValue).sorted(), forKey: Key.finderHiddenFields) }
    }
    var finderOnDesktop: Bool { didSet { defaults.set(finderOnDesktop, forKey: Key.finderOnDesktop) } }
    var finderForFolders: Bool { didSet { defaults.set(finderForFolders, forKey: Key.finderForFolders) } }
    /// Any key (Space for Quick Look, Return to rename, typing to select) closes the card.
    var finderClosesOnKeyPress: Bool { didSet { defaults.set(finderClosesOnKeyPress, forKey: Key.finderClosesOnKeyPress) } }
    var finderCopiesDetails: Bool { didSet { defaults.set(finderCopiesDetails, forKey: Key.finderCopiesDetails) } }
    var finderOffersQuit: Bool { didSet { defaults.set(finderOffersQuit, forKey: Key.finderOffersQuit) } }
    /// Images, videos, and audio show large, with their details beside or below.
    var finderMediaPreviews: Bool { didSet { defaults.set(finderMediaPreviews, forKey: Key.finderMediaPreviews) } }
    /// Audio in a large preview plays at once, rather than on its play button.
    var finderAutoplayAudio: Bool { didSet { defaults.set(finderAutoplayAudio, forKey: Key.finderAutoplayAudio) } }

    // Weather
    /// The weather popup for the Weather menu bar item.
    var weatherEnabled: Bool { didSet { defaults.set(weatherEnabled, forKey: Key.weatherEnabled) } }
    var weatherProvider: WeatherProviderID { didSet { defaults.set(weatherProvider.rawValue, forKey: Key.weatherProvider) } }
    /// Nil until one is chosen; nothing is looked up before then.
    var weatherLocation: WeatherLocationChoice? {
        didSet { defaults.set(weatherLocation.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.weatherLocation) }
    }
    var weatherUnits: WeatherUnits { didSet { defaults.set(try? JSONEncoder().encode(weatherUnits), forKey: Key.weatherUnits) } }
    var weatherHiddenSections: Set<WeatherSection> {
        didSet { defaults.set(weatherHiddenSections.map(\.rawValue).sorted(), forKey: Key.weatherHiddenSections) }
    }
    /// US alerts from the National Weather Service, for providers without alerts of their own.
    var weatherUsesNWSAlerts: Bool { didSet { defaults.set(weatherUsesNWSAlerts, forKey: Key.weatherUsesNWSAlerts) } }

    // macOS
    /// The network popup for the Wi-Fi menu bar item.
    var networkEnabled: Bool { didSet { defaults.set(networkEnabled, forKey: Key.networkEnabled) } }
    /// Whether the network popup asks addr.fyi for the public address.
    var networkLooksUpPublicAddress: Bool {
        didSet { defaults.set(networkLooksUpPublicAddress, forKey: Key.networkLooksUpPublicAddress) }
    }

    // Advanced
    var showsInspector: Bool { didSet { defaults.set(showsInspector, forKey: Key.showsInspector) } }

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.previewsEnabled: true,
            Key.activation: Activation.always.rawValue,
            Key.activationKey: ModifierKey.option.rawValue,
            Key.hoverDelay: 150.0,
            Key.skipWebmail: true,
            Key.previewsInOtherApps: false,
            Key.otherAppsSkipEmail: true,
            Key.otherAppsKnownSitesOnly: true,
            Key.otherAppsNeedKey: false,
            Key.showImages: true,
            Key.showAlbums: true,
            Key.showVideos: true,
            Key.showEmbeds: true,
            Key.showCards: true,
            Key.minimumEnlargement: 1.2,
            Key.maximumSize: 1.0,
            Key.largestImageMegabytes: 25,
            Key.showsNotch: true,
            Key.imageScroll: ImageScroll.zoom.rawValue,
            Key.videoScroll: VideoScroll.scrub.rawValue,
            Key.notchVideoScroll: VideoScroll.volume.rawValue,
            Key.videoScrubSeconds: 2,
            Key.videoSound: VideoSound.remember.rawValue,
            Key.videoMuted: true,
            Key.videoVolume: 1.0,
            Key.loopVideos: true,
            Key.resumeVideos: true,
            Key.showsInspector: false,
            Key.finderCards: true,
            Key.finderDelay: 600.0,
            Key.finderPathStyle: PathStyle.full.rawValue,
            Key.finderOnDesktop: true,
            Key.finderForFolders: true,
            Key.finderClosesOnKeyPress: true,
            Key.finderCopiesDetails: true,
            Key.finderOffersQuit: true,
            Key.finderMediaPreviews: true,
            Key.finderAutoplayAudio: false,
            Key.weatherEnabled: true,
            Key.weatherProvider: WeatherProviderID.openMeteo.rawValue,
            Key.weatherUsesNWSAlerts: true,
            Key.networkEnabled: true,
            Key.networkLooksUpPublicAddress: true,
        ])
        self.defaults = defaults
        previewsEnabled = defaults.bool(forKey: Key.previewsEnabled)
        activation = defaults.string(forKey: Key.activation).flatMap(Activation.init(rawValue:)) ?? .always
        activationKey = defaults.string(forKey: Key.activationKey).flatMap(ModifierKey.init(rawValue:)) ?? .option
        hoverDelay = max(defaults.double(forKey: Key.hoverDelay), Self.shortestHoverDelay)
        excludedApps = defaults.data(forKey: Key.excludedApps).flatMap { try? JSONDecoder().decode([ExcludedApp].self, from: $0) } ?? []
        skippedWebsites = defaults.stringArray(forKey: Key.skippedWebsites) ?? []
        skipsWebmail = defaults.bool(forKey: Key.skipWebmail)
        pauseShortcut = defaults.data(forKey: Key.pauseShortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
        previewsInOtherApps = defaults.bool(forKey: Key.previewsInOtherApps)
        otherAppsSkipEmail = defaults.bool(forKey: Key.otherAppsSkipEmail)
        otherAppsKnownSitesOnly = defaults.bool(forKey: Key.otherAppsKnownSitesOnly)
        otherAppsNeedKey = defaults.bool(forKey: Key.otherAppsNeedKey)
        showImages = defaults.bool(forKey: Key.showImages)
        showAlbums = defaults.bool(forKey: Key.showAlbums)
        showVideos = defaults.bool(forKey: Key.showVideos)
        showEmbeds = defaults.bool(forKey: Key.showEmbeds)
        showCards = defaults.bool(forKey: Key.showCards)
        disabledSites = Set((defaults.stringArray(forKey: Key.disabledSites) ?? []).compactMap(MediaSite.init(rawValue:)))
        minimumEnlargement = defaults.double(forKey: Key.minimumEnlargement)
        maximumSize = defaults.double(forKey: Key.maximumSize)
        largestImageMegabytes = defaults.integer(forKey: Key.largestImageMegabytes)
        showsNotch = defaults.bool(forKey: Key.showsNotch)
        imageScroll = defaults.string(forKey: Key.imageScroll).flatMap(ImageScroll.init(rawValue:)) ?? .zoom
        videoScroll = defaults.string(forKey: Key.videoScroll).flatMap(VideoScroll.init(rawValue:)) ?? .scrub
        notchVideoScroll = defaults.string(forKey: Key.notchVideoScroll).flatMap(VideoScroll.init(rawValue:)) ?? .volume
        videoScrubSeconds = defaults.integer(forKey: Key.videoScrubSeconds)
        videoSound = defaults.string(forKey: Key.videoSound).flatMap(VideoSound.init(rawValue:)) ?? .remember
        videoMuted = defaults.bool(forKey: Key.videoMuted)
        videoVolume = defaults.double(forKey: Key.videoVolume)
        loopVideos = defaults.bool(forKey: Key.loopVideos)
        resumeVideos = defaults.bool(forKey: Key.resumeVideos)
        showsInspector = defaults.bool(forKey: Key.showsInspector)
        finderCards = defaults.bool(forKey: Key.finderCards)
        finderDelay = defaults.double(forKey: Key.finderDelay)
        finderPathStyle = defaults.string(forKey: Key.finderPathStyle).flatMap(PathStyle.init(rawValue:)) ?? .full
        finderHiddenFields = Set((defaults.stringArray(forKey: Key.finderHiddenFields) ?? []).compactMap(FileCardField.init(rawValue:)))
        finderOnDesktop = defaults.bool(forKey: Key.finderOnDesktop)
        finderForFolders = defaults.bool(forKey: Key.finderForFolders)
        finderClosesOnKeyPress = defaults.bool(forKey: Key.finderClosesOnKeyPress)
        finderCopiesDetails = defaults.bool(forKey: Key.finderCopiesDetails)
        finderOffersQuit = defaults.bool(forKey: Key.finderOffersQuit)
        finderMediaPreviews = defaults.bool(forKey: Key.finderMediaPreviews)
        finderAutoplayAudio = defaults.bool(forKey: Key.finderAutoplayAudio)
        weatherEnabled = defaults.bool(forKey: Key.weatherEnabled)
        weatherProvider = defaults.string(forKey: Key.weatherProvider).flatMap(WeatherProviderID.init(rawValue:)) ?? .openMeteo
        weatherLocation = defaults.data(forKey: Key.weatherLocation).flatMap { try? JSONDecoder().decode(WeatherLocationChoice.self, from: $0) }
        weatherUnits = defaults.data(forKey: Key.weatherUnits).flatMap { try? JSONDecoder().decode(WeatherUnits.self, from: $0) } ?? .forLocale()
        weatherHiddenSections = Set((defaults.stringArray(forKey: Key.weatherHiddenSections) ?? []).compactMap(WeatherSection.init(rawValue:)))
        weatherUsesNWSAlerts = defaults.bool(forKey: Key.weatherUsesNWSAlerts)
        networkEnabled = defaults.bool(forKey: Key.networkEnabled)
        networkLooksUpPublicAddress = defaults.bool(forKey: Key.networkLooksUpPublicAddress)
    }

    var filter: PreviewFilter {
        PreviewFilter(images: showImages, albums: showAlbums, videos: showVideos, embeds: showEmbeds, cards: showCards,
                      files: finderCards, filesOnDesktop: finderOnDesktop, folders: finderForFolders, weather: weatherEnabled,
                      network: networkEnabled, disabledSites: disabledSites)
    }

    var otherApps: OtherAppsPolicy {
        // Settings greys the key out while previews appear except while holding it: needing it too would
        // mean never.
        OtherAppsPolicy(enabled: previewsInOtherApps, skipsEmail: otherAppsSkipEmail, knownSitesOnly: otherAppsKnownSitesOnly,
                        needsKey: otherAppsNeedKey && activation != .unlessHoldingKey)
    }

    /// Whether the activation key matters anywhere, so pressing or releasing it should show or hide a
    /// preview at once.
    var usesActivationKey: Bool {
        activation != .always || (previewsInOtherApps && otherAppsNeedKey)
    }

    var fileCard: FileCardOptions {
        FileCardOptions(hidden: finderHiddenFields, pathStyle: finderPathStyle, offersQuit: finderOffersQuit,
                        copiesDetails: finderCopiesDetails)
    }

    /// Puts every Finder setting back as it first was. Tests check these match the registered defaults.
    func restoreFinderDefaults() {
        finderCards = true
        finderDelay = 600
        finderPathStyle = .full
        finderHiddenFields = []
        finderOnDesktop = true
        finderForFolders = true
        finderClosesOnKeyPress = true
        finderCopiesDetails = true
        finderOffersQuit = true
        finderMediaPreviews = true
        finderAutoplayAudio = false
    }

    func previewsAllowed(holding flags: NSEvent.ModifierFlags) -> Bool {
        let held = flags.contains(activationKey.flag)
        return switch activation {
        case .always: true
        case .whileHoldingKey: held
        case .unlessHoldingKey: !held
        }
    }

    var videosStartMuted: Bool {
        switch videoSound {
        case .remember: videoMuted
        case .muted: true
        case .unmuted: false
        }
    }

    /// What the inspector needs to know. With the inspector on, every app is looked at in full.
    var inspectionPolicy: InspectionPolicy {
        showsInspector ? InspectionPolicy() : InspectionPolicy(skipped: Set(excludedApps.map(\.bundleID)), includesOtherApps: previewsInOtherApps)
    }

    /// Whether resting the cursor is worth a look now: not while previews wait for a key that isn't held,
    /// or one that is, unless the inspector wants to see.
    func inspectsOnRest(holding flags: NSEvent.ModifierFlags) -> Bool {
        showsInspector || (previewsEnabled && previewsAllowed(holding: flags))
    }

    /// Whether `page` is on a website in `skippedWebsites`, or is webmail while that's skipped.
    func skips(page: URL?) -> Bool {
        SkippedWebsites.contains(page, in: skippedWebsites) || (skipsWebmail && Webmail.contains(page))
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains { $0.bundleID == bundleID }
    }
}

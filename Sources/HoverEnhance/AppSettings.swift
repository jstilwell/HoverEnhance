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
        static let showImages = "showImages"
        static let showAlbums = "showAlbums"
        static let showVideos = "showVideos"
        static let showEmbeds = "showEmbeds"
        static let showCards = "showCards"
        static let disabledSites = "disabledSites"
        static let minimumEnlargement = "minimumEnlargement"
        static let maximumSize = "maximumSize"
        static let showsNotch = "showsNotch"
        static let imageScroll = "imageScroll"
        static let videoScroll = "videoScroll"
        static let videoSound = "videoSound"
        static let videoMuted = "videoMuted"
        static let videoVolume = "videoVolume"
        static let loopVideos = "loopVideos"
        static let resumeVideos = "resumeVideos"
        static let showsInspector = "showsInspector"
        static let finderCards = "finderCards"
        static let finderDelay = "finderDelay"
        static let finderShowsPath = "finderShowsPath"
        static let finderPathStyle = "finderPathStyle"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // General
    var previewsEnabled: Bool { didSet { defaults.set(previewsEnabled, forKey: Key.previewsEnabled) } }
    var activation: Activation { didSet { defaults.set(activation.rawValue, forKey: Key.activation) } }
    var activationKey: ModifierKey { didSet { defaults.set(activationKey.rawValue, forKey: Key.activationKey) } }
    /// Milliseconds the cursor rests before a preview starts.
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    var excludedApps: [ExcludedApp] {
        didSet { defaults.set(try? JSONEncoder().encode(excludedApps), forKey: Key.excludedApps) }
    }

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
    var showsNotch: Bool { didSet { defaults.set(showsNotch, forKey: Key.showsNotch) } }
    var imageScroll: ImageScroll { didSet { defaults.set(imageScroll.rawValue, forKey: Key.imageScroll) } }

    // Video
    var videoSound: VideoSound { didSet { defaults.set(videoSound.rawValue, forKey: Key.videoSound) } }
    /// The player's last mute state, used when `videoSound` is `.remember`.
    var videoMuted: Bool { didSet { defaults.set(videoMuted, forKey: Key.videoMuted) } }
    var videoVolume: Double { didSet { defaults.set(videoVolume, forKey: Key.videoVolume) } }
    var loopVideos: Bool { didSet { defaults.set(loopVideos, forKey: Key.loopVideos) } }
    var resumeVideos: Bool { didSet { defaults.set(resumeVideos, forKey: Key.resumeVideos) } }
    var videoScroll: VideoScroll { didSet { defaults.set(videoScroll.rawValue, forKey: Key.videoScroll) } }

    // Finder
    var finderCards: Bool { didSet { defaults.set(finderCards, forKey: Key.finderCards) } }
    /// Milliseconds the cursor rests on a file before its card appears; never less than `hoverDelay`.
    var finderDelay: Double { didSet { defaults.set(finderDelay, forKey: Key.finderDelay) } }
    var finderShowsPath: Bool { didSet { defaults.set(finderShowsPath, forKey: Key.finderShowsPath) } }
    var finderPathStyle: PathStyle { didSet { defaults.set(finderPathStyle.rawValue, forKey: Key.finderPathStyle) } }

    // Advanced
    var showsInspector: Bool { didSet { defaults.set(showsInspector, forKey: Key.showsInspector) } }

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.previewsEnabled: true,
            Key.activation: Activation.always.rawValue,
            Key.activationKey: ModifierKey.option.rawValue,
            Key.hoverDelay: 150.0,
            Key.showImages: true,
            Key.showAlbums: true,
            Key.showVideos: true,
            Key.showEmbeds: true,
            Key.showCards: true,
            Key.minimumEnlargement: 1.2,
            Key.maximumSize: 1.0,
            Key.showsNotch: true,
            Key.imageScroll: ImageScroll.zoom.rawValue,
            Key.videoScroll: VideoScroll.scrub.rawValue,
            Key.videoSound: VideoSound.remember.rawValue,
            Key.videoMuted: true,
            Key.videoVolume: 1.0,
            Key.loopVideos: true,
            Key.resumeVideos: true,
            Key.showsInspector: false,
            Key.finderCards: true,
            Key.finderDelay: 600.0,
            Key.finderShowsPath: true,
            Key.finderPathStyle: PathStyle.full.rawValue,
        ])
        self.defaults = defaults
        previewsEnabled = defaults.bool(forKey: Key.previewsEnabled)
        activation = defaults.string(forKey: Key.activation).flatMap(Activation.init(rawValue:)) ?? .always
        activationKey = defaults.string(forKey: Key.activationKey).flatMap(ModifierKey.init(rawValue:)) ?? .option
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        excludedApps = defaults.data(forKey: Key.excludedApps).flatMap { try? JSONDecoder().decode([ExcludedApp].self, from: $0) } ?? []
        showImages = defaults.bool(forKey: Key.showImages)
        showAlbums = defaults.bool(forKey: Key.showAlbums)
        showVideos = defaults.bool(forKey: Key.showVideos)
        showEmbeds = defaults.bool(forKey: Key.showEmbeds)
        showCards = defaults.bool(forKey: Key.showCards)
        disabledSites = Set((defaults.stringArray(forKey: Key.disabledSites) ?? []).compactMap(MediaSite.init(rawValue:)))
        minimumEnlargement = defaults.double(forKey: Key.minimumEnlargement)
        maximumSize = defaults.double(forKey: Key.maximumSize)
        showsNotch = defaults.bool(forKey: Key.showsNotch)
        imageScroll = defaults.string(forKey: Key.imageScroll).flatMap(ImageScroll.init(rawValue:)) ?? .zoom
        videoScroll = defaults.string(forKey: Key.videoScroll).flatMap(VideoScroll.init(rawValue:)) ?? .scrub
        videoSound = defaults.string(forKey: Key.videoSound).flatMap(VideoSound.init(rawValue:)) ?? .remember
        videoMuted = defaults.bool(forKey: Key.videoMuted)
        videoVolume = defaults.double(forKey: Key.videoVolume)
        loopVideos = defaults.bool(forKey: Key.loopVideos)
        resumeVideos = defaults.bool(forKey: Key.resumeVideos)
        showsInspector = defaults.bool(forKey: Key.showsInspector)
        finderCards = defaults.bool(forKey: Key.finderCards)
        finderDelay = defaults.double(forKey: Key.finderDelay)
        finderShowsPath = defaults.bool(forKey: Key.finderShowsPath)
        finderPathStyle = defaults.string(forKey: Key.finderPathStyle).flatMap(PathStyle.init(rawValue:)) ?? .full
    }

    var filter: PreviewFilter {
        PreviewFilter(images: showImages, albums: showAlbums, videos: showVideos, embeds: showEmbeds, cards: showCards,
                      files: finderCards, disabledSites: disabledSites)
    }

    var fileCard: FileCardOptions {
        FileCardOptions(path: finderShowsPath, pathStyle: finderPathStyle)
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

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains { $0.bundleID == bundleID }
    }
}

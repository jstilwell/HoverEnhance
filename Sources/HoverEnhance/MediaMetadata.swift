import AVFoundation

/// What an audio or video file says about itself in its own tags (ID3, iTunes, QuickTime), which
/// Spotlight may not have indexed, and what its tracks are. Read with AVFoundation; nothing plays.
struct MediaMetadata: Sendable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var composer: String?
    var genre: String?
    var year: String?
    /// "3 of 12", or "3" without a total.
    var track: String?
    var disc: String?
    /// The cover, as image data.
    var artwork: Data?
    /// When a video was recorded.
    var recorded: Date?
    /// What it was recorded with, such as "Apple iPhone 15 Pro".
    var device: String?
    var frameRate: Double?
    var isHDR = false
    /// "48 kHz stereo".
    var audio: String?
    /// Whether there's a picture: a video, as opposed to audio.
    var hasVideo = false
    /// The video's size as shown, after any rotation.
    var pixelSize: CGSize?
    /// Seconds.
    var duration: Double?

    var isEmpty: Bool { self == MediaMetadata() }

    /// Nil for files AVFoundation can't open, or that have nothing to say.
    static func read(_ url: URL) async -> MediaMetadata? {
        let asset = AVURLAsset(url: url)
        guard let (items, tracks, duration) = try? await asset.load(.metadata, .tracks, .duration) else { return nil }
        var tags: [AVMetadataIdentifier: Tag] = [:]
        for item in items {
            guard let identifier = item.identifier, tags[identifier] == nil else { continue }
            tags[identifier] = Tag(string: try? await item.load(.stringValue), data: try? await item.load(.dataValue),
                                   date: try? await item.load(.dateValue))
        }
        var metadata = MediaMetadata(tags: tags)
        for track in tracks {
            switch track.mediaType {
            case .video:
                metadata.hasVideo = true
                guard metadata.pixelSize == nil,
                      let (rate, size, transform, traits) = try? await track.load(.nominalFrameRate, .naturalSize, .preferredTransform, .mediaCharacteristics)
                else { continue }
                let shown = size.applying(transform)
                metadata.pixelSize = CGSize(width: abs(shown.width), height: abs(shown.height))
                metadata.frameRate = rate > 0 ? Double(rate) : nil
                metadata.isHDR = traits.contains(.containsHDRVideo)
            case .audio:
                guard metadata.audio == nil, let formats = try? await track.load(.formatDescriptions),
                      let format = formats.first.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }) else { continue }
                metadata.audio = audioDescription(sampleRate: format.mSampleRate, channels: Int(format.mChannelsPerFrame))
            default:
                continue
            }
        }
        metadata.duration = duration.seconds.isFinite && duration.seconds > 0 ? duration.seconds : nil
        return metadata.isEmpty ? nil : metadata
    }

    /// One tag's value, in whichever forms it has.
    struct Tag: Sendable, Equatable {
        var string: String?
        var data: Data?
        var date: Date?
    }

    /// The first tag found for each detail, across the tag formats that hold it.
    init(tags: [AVMetadataIdentifier: Tag] = [:]) {
        func string(_ identifiers: AVMetadataIdentifier...) -> String? {
            identifiers.lazy.compactMap { tags[$0]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        }
        func data(_ identifiers: AVMetadataIdentifier...) -> Data? {
            identifiers.lazy.compactMap { tags[$0]?.data }.first { !$0.isEmpty }
        }
        title = string(.id3MetadataTitleDescription, .iTunesMetadataSongName, .quickTimeMetadataTitle, .commonIdentifierTitle)
        artist = string(.id3MetadataLeadPerformer, .iTunesMetadataArtist, .quickTimeMetadataArtist, .commonIdentifierArtist)
        album = string(.id3MetadataAlbumTitle, .iTunesMetadataAlbum, .quickTimeMetadataAlbum, .commonIdentifierAlbumName)
        albumArtist = string(.id3MetadataBand, .iTunesMetadataAlbumArtist)
        composer = string(.id3MetadataComposer, .iTunesMetadataComposer, .quickTimeMetadataComposer)
        genre = string(.id3MetadataContentType, .iTunesMetadataUserGenre, .quickTimeMetadataGenre).flatMap(Self.genre)
        year = string(.id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate, .quickTimeMetadataYear)
            .flatMap { $0.firstMatch(of: /\d{4}/).map { String($0.output) } }
        track = string(.id3MetadataTrackNumber).flatMap(Self.position) ?? data(.iTunesMetadataTrackNumber).flatMap(Self.position)
        disc = string(.id3MetadataPartOfASet).flatMap(Self.position) ?? data(.iTunesMetadataDiscNumber).flatMap(Self.position)
        artwork = data(.id3MetadataAttachedPicture, .iTunesMetadataCoverArt, .quickTimeMetadataArtwork, .commonIdentifierArtwork)
        recorded = [AVMetadataIdentifier.quickTimeMetadataCreationDate, .commonIdentifierCreationDate].lazy.compactMap { identifier in
            tags[identifier].flatMap { $0.date ?? $0.string.flatMap(Self.date) }
        }.first
        device = FileDetails.cameraName(make: string(.quickTimeMetadataMake, .commonIdentifierMake),
                                        model: string(.quickTimeMetadataModel, .commonIdentifierModel))
    }

    /// ID3's "3/12" as "3 of 12", and "3" as it is.
    static func position(_ text: String) -> String? {
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let number = parts.first.flatMap({ Int($0) }), number > 0 else { return nil }
        guard parts.count > 1, let total = Int(parts[1]), total > 0 else { return String(number) }
        return "\(number) of \(total)"
    }

    /// iTunes's track and disc atoms: two reserved bytes, then the number and the total, big-endian.
    static func position(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        let number = Int(bytes[2]) << 8 | Int(bytes[3]), total = Int(bytes[4]) << 8 | Int(bytes[5])
        guard number > 0 else { return nil }
        return total > 0 ? "\(number) of \(total)" : String(number)
    }

    /// ID3v1 genres appear as "(13)", sometimes followed by the name; only a name is worth showing.
    static func genre(_ text: String) -> String? {
        guard let match = text.firstMatch(of: /^\(\d+\)(.*)$/) else { return text }
        let rest = match.1.trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// QuickTime's creation date, written as ISO 8601 text.
    static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601)) ?? ISO8601DateFormatter().date(from: text)
    }

    /// "48 kHz stereo", "22.05 kHz mono", "48 kHz, 6 channels".
    static func audioDescription(sampleRate: Double, channels: Int) -> String? {
        guard sampleRate > 0 else { return nil }
        let kilohertz = sampleRate / 1000
        let rate = (kilohertz.rounded() == kilohertz ? String(Int(kilohertz)) : String(format: "%g", kilohertz)) + " kHz"
        return switch channels {
        case 1: rate + " mono"
        case 2: rate + " stereo"
        case let count where count > 2: "\(rate), \(count) channels"
        default: rate
        }
    }
}

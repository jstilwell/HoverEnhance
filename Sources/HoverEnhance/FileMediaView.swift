import AVKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The kinds of Finder file shown large, with their details beside or below.
enum FileMediaKind: Equatable, Sendable {
    case image, video, audio

    /// Audio and video need what their tracks say, from `FileDetails.addMedia`, to tell them apart:
    /// an .mp4 can hold sound alone.
    init?(details: FileDetails) {
        guard let type = details.contentType else { return nil }
        if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .audiovisualContent), let media = details.media {
            self = media.hasVideo ? .video : .audio
        } else {
            return nil
        }
    }
}

/// A Finder image, video, or audio file shown large, with its card beside or below it.
struct FileMediaCardView: View {
    enum Content {
        case image(NSImage)
        case video(AVPlayer)
        case audio(artwork: NSImage?, model: AudioPreviewModel)
    }

    static let detailsWidth: CGFloat = 340
    /// The artwork's side when there's room; songs have no size of their own.
    static let artworkSize = CGSize(width: 320, height: 320)

    let card: FileCard
    let content: Content
    let layout: FileMediaLayout
    let mediaSize: CGSize

    var body: some View {
        let stack = layout == .beside
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        stack {
            media
                .frame(width: mediaSize.width, height: mediaSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            // Below the media they're as wide as it, rather than a narrow column under it.
            FileCardView(card: card, showsImage: false, width: layout == .below ? max(Self.detailsWidth, mediaSize.width) : Self.detailsWidth)
        }
    }

    @ViewBuilder
    private var media: some View {
        switch content {
        case .image(let image):
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        case .video(let player):
            PlayerView(player: player)
        case .audio(let artwork, let model):
            AudioArtworkView(artwork: artwork, model: model)
        }
    }
}

/// The preview's video player, with its own controls.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}

/// Whether a song in a preview is playing, and the button's action.
@MainActor @Observable
final class AudioPreviewModel {
    var isPlaying = false
    @ObservationIgnored let toggle: @MainActor () -> Void

    init(toggle: @escaping @MainActor () -> Void) {
        self.toggle = toggle
    }
}

/// A song's artwork, or a note in its place, with a play button.
private struct AudioArtworkView: View {
    let artwork: NSImage?
    let model: AudioPreviewModel

    var body: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note").font(.system(size: 64, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Button { model.toggle() } label: {
                Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
                    .shadow(radius: 3)
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            .padding(12)
        }
    }
}

/// Images on disk, read for a large preview, with the same limits as images from the web.
enum LocalImage {
    /// The image's size in pixels as shown (after its EXIF orientation), without decoding it.
    static func pixelSize(of url: URL) -> CGSize? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { ImageDecoder.Picture($0) }?.pixelSize
    }

    /// Decoded with its long edge at most `maxPixelSize`; animations whole, so they play.
    static func load(_ url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let picture = ImageDecoder.Picture(source),
              picture.isDecodable else { return nil }
        if picture.isAnimation { return NSImage(contentsOf: url) }
        return ImageDecoder.thumbnail(of: picture, in: source, maxPixelSize: maxPixelSize)
    }
}

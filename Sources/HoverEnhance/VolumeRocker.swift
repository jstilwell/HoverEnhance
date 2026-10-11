import AppKit

/// The volume beside the notch during a video: a pill with a speaker symbol over a level that fills
/// from the bottom. It's click-through; scrolling on it, or on the notch, changes the volume.
@MainActor
final class VolumeRockerView: NSVisualEffectView {
    private let symbol = NSImageView()
    private let track = NSView()
    private let fill = NSView()

    /// From 0 to 1.
    var level: Float = 1 { didSet { update() } }
    var isMuted = false { didSet { update() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover
        blendingMode = .behindWindow
        // The rocker is never in a key window; without this it would draw the flat inactive look.
        state = .active
        wantsLayer = true
        layer?.masksToBounds = true
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        symbol.contentTintColor = .secondaryLabelColor
        for view in [track, fill] {
            view.wantsLayer = true
            addSubview(view)
        }
        addSubview(symbol)
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func update() {
        let shown = isMuted ? 0 : level
        let name = switch shown {
        case ...0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
        symbol.image = NSImage(systemSymbolName: name, accessibilityDescription: "Volume")
        setAccessibilityValue(isMuted ? "Muted" : "\(Int((level * 100).rounded()))%")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        let inset: CGFloat = 5
        let symbolSize: CGFloat = 12
        symbol.frame = CGRect(x: (bounds.width - symbolSize) / 2, y: bounds.height - inset - symbolSize, width: symbolSize, height: symbolSize)
        let trackWidth: CGFloat = 4
        let trackHeight = max(symbol.frame.minY - 5 - inset, 0)
        track.frame = CGRect(x: (bounds.width - trackWidth) / 2, y: inset, width: trackWidth, height: trackHeight)
        let shown = CGFloat(isMuted ? 0 : min(max(level, 0), 1))
        fill.frame = CGRect(x: track.frame.minX, y: inset, width: trackWidth, height: trackHeight * shown)
        // Layer colors are fixed values, so they're set again whenever the appearance may have changed.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
            fill.layer?.backgroundColor = NSColor.labelColor.cgColor
        }
        // A rounding larger than a short fill would draw a speck; nothing at all shows silence.
        track.layer?.cornerRadius = trackWidth / 2
        fill.layer?.cornerRadius = min(trackWidth, fill.frame.height) / 2
        fill.isHidden = fill.frame.height < 0.5
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}

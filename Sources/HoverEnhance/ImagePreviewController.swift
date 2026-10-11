import AppKit

/// Decides when to show a full-size preview for what the cursor is resting on, and when to hide it.
@MainActor
final class ImagePreviewController {
    var isEnabled = true {
        didSet { if !isEnabled { reset() } }
    }

    private let loader = ImageLoader()
    private let panel = PreviewPanel()
    private var target: Target?
    private var loadTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    private struct Target: Equatable {
        let candidates: [URL]
        /// The hovered element in global top-left-origin coordinates; leaving it hides the preview.
        let area: CGRect
    }

    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }

    func hovered(_ info: HoverInfo) {
        guard isEnabled else { return }
        let candidates = ImageResolver.candidates(for: info)
        guard !candidates.isEmpty, let cursor = CGEvent(source: nil)?.location else {
            reset()
            return
        }
        // Still on the same thing: it's loading, showing, or was dismissed by a click.
        if target?.candidates == candidates { return }

        reset()
        let elementFrame = info.imageFrame ?? info.frame
        let newTarget = Target(
            candidates: candidates,
            area: elementFrame?.insetBy(dx: -4, dy: -4) ?? CGRect(origin: cursor, size: .zero).insetBy(dx: -24, dy: -24)
        )
        target = newTarget
        loadTask = Task {
            let image = await loader.load(candidates, page: info.pageURL, maxPixelSize: Self.maxPixelSize())
            guard let image, !Task.isCancelled, target == newTarget else { return }
            // Nothing to gain if the image isn't meaningfully bigger than it already appears.
            if let shown = elementFrame?.size,
               image.pixelSize.width <= shown.width * 1.2, image.pixelSize.height <= shown.height * 1.2 { return }
            panel.show(image)
        }
    }

    func mouseMoved(to point: CGPoint) {
        if let target, !target.area.contains(point) { reset() }
    }

    /// Hides the preview but remembers the target, so it stays hidden until the cursor moves on.
    func dismiss() {
        loadTask?.cancel()
        panel.hide()
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        target = nil
        panel.hide()
    }

    /// Longest screen edge in pixels; larger images are downsampled to this when decoded.
    private static func maxPixelSize() -> Int {
        Int(NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 4096)
    }
}

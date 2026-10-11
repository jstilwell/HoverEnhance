import AppKit
import SwiftUI

/// The first thing shown without Accessibility access: what HoverEnhance does, and how to let it see
/// what's under the cursor. Nothing else of the app runs until access is on. Once it is, the window
/// says where the app lives.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the window closes, by the user or by Done.
    var onClose: (() -> Void)?
    private let access: AccessibilityWatcher
    private var accessObservation: Task<Void, Never>?

    /// `isReturning` is for when the app ran before and has lost access, rather than a first launch.
    init(access: AccessibilityWatcher, isReturning: Bool, openSettings: @escaping @MainActor () -> Void) {
        self.access = access
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to HoverEnhance"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let view = WelcomeView(access: access, isReturning: isReturning, openSettings: openSettings) { [weak window] in window?.close() }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        window.contentViewController = host
        window.delegate = self
        followAccess()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        guard let window else { return }
        // A menu bar app isn't frontmost on its own.
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    /// Floats over System Settings while access is off, so the icon can be dragged into its list; comes
    /// forward once access is on, to say so.
    private func followAccess() {
        window?.level = access.isGranted ? .normal : .floating
        withObservationTracking { _ = access.isGranted } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.access.isGranted, self.window?.isVisible == true { self.show() }
                self.followAccess()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

struct WelcomeView: View {
    let access: AccessibilityWatcher
    let isReturning: Bool
    let openSettings: @MainActor () -> Void
    let done: @MainActor () -> Void
    @State private var showsTroubleshooting = false

    var body: some View {
        Group {
            if access.isGranted { ready } else { setup }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Before access

    private var setup: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isReturning ? "HoverEnhance needs Accessibility access again" : "Welcome to HoverEnhance")
                        .font(.title2.weight(.semibold))
                    Text("Rest the cursor on an image, a link, or a file, and HoverEnhance shows what's there.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(isReturning
                 ? "macOS turned off its Accessibility access, so it can't see what's under the cursor. Turn it back on to carry on."
                 : "To see what's under the cursor, HoverEnhance needs Accessibility access. It only looks at the thing you're resting on, and never records what you type.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                Step(number: 1, title: "Open Accessibility in System Settings") {
                    Button("Open System Settings") { AccessibilityPermission.openSettings() }
                }
                Step(number: 2, title: "Drag HoverEnhance into the list",
                     detail: "Or click + below the list and choose HoverEnhance.") {
                    DragHandle()
                }
                Step(number: 3, title: "Turn on the switch next to it",
                     detail: "macOS may ask for your password or Touch ID.") {
                    EmptyView()
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for access. This window moves on by itself.").foregroundStyle(.secondary)
            }

            DisclosureGroup("Listed and switched on, but nothing happens?", isExpanded: $showsTroubleshooting) {
                Text("macOS can hold on to an older copy of HoverEnhance, such as one that was rebuilt or updated since. In the list, select HoverEnhance and click − to remove it, then drag it in again from here and turn it on.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            HStack {
                Spacer()
                Button("Quit HoverEnhance") { NSApp.terminate(nil) }
            }
        }
        .padding(28)
        .padding(.top, 8)
    }

    // MARK: - After access

    private var ready: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                }
            Text("HoverEnhance is ready").font(.title2.weight(.semibold))
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("It runs in the menu bar:")
                    Image(nsImage: MenuBarIcon.image())
                }
                Text("Rest the cursor on an image or a link in your browser, or on a file in Finder.")
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Open Settings") {
                    openSettings()
                    done()
                }
                Button("Done") { done() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(32)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }
}

/// A numbered step with whatever control it needs on the right.
private struct Step<Control: View>: View {
    let number: Int
    let title: String
    var detail: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control()
        }
    }
}

/// The app's icon, to drag into the Accessibility list in System Settings.
private struct DragHandle: View {
    var body: some View {
        HStack(spacing: 6) {
            AppIconDragSource.Representable()
                .frame(width: 44, height: 44)
            Image(systemName: "arrow.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(.secondary.opacity(0.6))
        )
        .help("Drag into the Accessibility list")
    }
}

/// Drags the app itself, as Finder would, so System Settings adds it to the list it's dropped on.
final class AppIconDragSource: NSView, NSDraggingSource {
    private let bundleURL = Bundle.main.bundleURL
    private let icon = NSApp.applicationIconImage ?? NSImage()

    struct Representable: NSViewRepresentable {
        func makeNSView(context: Context) -> AppIconDragSource { AppIconDragSource() }
        func updateNSView(_ view: AppIconDragSource, context: Context) {}
    }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: bounds)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    /// System Settings is in front while this is dragged from.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
}

/// The status item's image, also shown in the welcome window.
enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "HoverEnhance") ?? NSImage()
        image.isTemplate = true
        return image
    }
}

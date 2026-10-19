import SwiftUI

/// Copy, Save, and Save As… under an image or video preview, shown while the cursor is on the preview.
struct PreviewActionBarView: View {
    /// Streams can't be saved, only their address copied.
    let canSave: Bool
    let shortcuts: [PreviewShortcut: Shortcut]
    let perform: (PreviewShortcut) -> Void

    static let height: CGFloat = 30

    var body: some View {
        HStack(spacing: 2) {
            button(.copy, title: "Copy", symbol: "doc.on.doc")
            button(.save, title: "Save", symbol: "square.and.arrow.down")
            button(.saveAs, title: "Save As…", symbol: "square.and.arrow.down.on.square")
        }
        .padding(.horizontal, 3)
        .frame(height: Self.height)
        .fixedSize()
    }

    private func button(_ action: PreviewShortcut, title: String, symbol: String) -> some View {
        let enabled = action == .copy || canSave
        let help = enabled ? shortcuts[action].map { "\(title) (\($0.label))" } ?? title : "Streamed videos can't be saved"
        return Button { perform(action) } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: Self.height - 6)
                .contentShape(Capsule())
        }
        .buttonStyle(BarButtonStyle())
        .disabled(!enabled)
        .help(help)
    }
}

/// Plain, with a tint while pressed, on the bar's own material.
private struct BarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.15 : 0)))
    }
}

import SwiftUI

/// What the preview shows for an image over the size limit: how big it is, with a way to load it anyway.
struct TooLargeCardView: View {
    let url: URL
    /// Its size, when the server said; otherwise it only ran past the limit.
    let bytes: Int64?
    let limit: Int64
    /// Loads it without the limit; false if that failed.
    let loadAnyway: @MainActor () async -> Bool

    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(headline).font(.headline)
                Text("That's over the \(Self.format(limit)) limit set in Settings → Previews, so it wasn't downloaded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let host = url.host() {
                    Text(host).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    Button("Load Anyway") {
                        isLoading = true
                        failed = false
                        Task {
                            failed = await !loadAnyway()
                            isLoading = false
                        }
                    }
                    .disabled(isLoading)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else if failed {
                        Text("It didn't load.").font(.callout).foregroundStyle(.red)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }

    private var headline: String {
        bytes.map { "This image is \(Self.format($0))" } ?? "This image is over \(Self.format(limit))"
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

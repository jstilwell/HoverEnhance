import SwiftUI

/// A picture on a card, filling its frame. It loads as previews do, through `ImageLoader`: within the size
/// limit, and without cookies for hosts outside Settings → Sites, which `AsyncImage`'s shared session
/// would keep.
struct CardImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url) {
            image = nil
            // Decoded as a preview of it would be, since the two share a cache.
            guard let url, case .loaded(let loaded) = await ImageLoader.shared.load(
                [url], page: nil, maxPixelSize: PreviewController.maxPixelSize(), byteLimit: AppSettings.shared.largestImageBytes
            ) else { return }
            image = loaded.image
        }
    }
}

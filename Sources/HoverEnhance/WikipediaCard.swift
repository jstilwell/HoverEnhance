import AppKit
import SwiftUI

/// What the preview shows for a link to a Wikipedia article, in the look of Wikipedia's own page
/// previews: its image, title, short description, and first paragraphs. Clicking it opens the article.
struct WikipediaCardView: View {
    let article: WikipediaArticle

    static let width: CGFloat = 440
    /// Wide images go across the top, no taller than this; others sit beside the text.
    private static let bannerHeight: CGFloat = 220
    private static let sideImage = CGSize(width: 120, height: 160)

    var body: some View {
        Button { NSWorkspace.shared.open(article.url) } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let image = article.image, isWide {
                    ArticleImage(url: image, size: CGSize(width: Self.width, height: bannerHeight))
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title)
                            .font(.system(size: 22, design: .serif))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let description = article.description {
                            Text(description)
                                .font(.system(size: 13))
                                .foregroundStyle(WikipediaTheme.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(article.extract)
                            .font(.system(size: 14))
                            .lineSpacing(2)
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                        Text(source)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WikipediaTheme.secondary)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let image = article.image, !isWide {
                        ArticleImage(url: image, size: Self.sideImage)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open “\(article.title)” on Wikipedia")
        .frame(width: Self.width, alignment: .leading)
        .foregroundStyle(WikipediaTheme.text)
        .background(WikipediaTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: PreviewPanel.cornerRadius - PreviewGeometry.padding))
        .environment(\.layoutDirection, article.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    private var isWide: Bool {
        guard let size = article.imageSize, size.height > 0 else { return false }
        return size.width / size.height >= 1.2
    }

    /// Wide images keep their shape, up to the banner's limit.
    private var bannerHeight: CGFloat {
        guard let size = article.imageSize, size.width > 0 else { return Self.bannerHeight }
        return min(Self.bannerHeight, (Self.width * size.height / size.width).rounded())
    }

    /// "Wikipedia", or "Wikipedia · German" for an article in another language than the Mac's.
    private var source: String {
        let current = Locale.current.language.languageCode?.identifier
        guard !article.language.isEmpty, article.language != current,
              let name = Locale.current.localizedString(forLanguageCode: article.language) else { return "Wikipedia" }
        return "Wikipedia · \(name)"
    }
}

private struct ArticleImage: View {
    let url: URL
    let size: CGSize

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            WikipediaTheme.placeholder
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Wikipedia's colors, light and dark.
enum WikipediaTheme {
    static let background = Color(light: 0xFFFFFF, dark: 0x101418)
    static let text = Color(light: 0x202122, dark: 0xEAECF0)
    static let secondary = Color(light: 0x54595D, dark: 0xA2A9B1)
    static let placeholder = Color(light: 0xEAECF0, dark: 0x27292D)
}

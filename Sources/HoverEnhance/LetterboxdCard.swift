import AppKit
import SwiftUI

/// What the preview shows for a link to Letterboxd, in Letterboxd's look: a film with its poster and
/// rating, a member's review, someone's films, or a list. Clicking it opens the page.
struct LetterboxdCardView: View {
    let card: LetterboxdCard

    static let width: CGFloat = 460
    static let padding: CGFloat = 16

    var body: some View {
        Group {
            switch card {
            case .film(let film): FilmCard(film: film, url: card.url)
            case .review(let review): ReviewCard(review: review, url: card.url)
            case .person(let person): PersonCard(person: person, url: card.url)
            case .list(let list): ListCard(list: list, url: card.url)
            }
        }
        .buttonStyle(.plain)
        .frame(width: Self.width, alignment: .leading)
        .foregroundStyle(LetterboxdTheme.text)
        .background(LetterboxdTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: PreviewPanel.cornerRadius - PreviewGeometry.padding))
        .environment(\.colorScheme, .dark)
    }
}

/// Opens the page when clicked. Cards are made of these rather than one big button, so a part of one,
/// like the review card's spoiler cover, can do something else.
private struct OpenButton<Label: View>: View {
    let url: URL
    @ViewBuilder let label: Label

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            label.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .help("Open on Letterboxd")
    }
}

private struct FilmCard: View {
    let film: LetterboxdFilm
    let url: URL

    var body: some View {
        OpenButton(url: url) {
            HStack(alignment: .top, spacing: 16) {
                Poster(url: film.poster, width: 140)
                VStack(alignment: .leading, spacing: 6) {
                    FilmTitle(title: film.title, year: film.year, size: 22)
                    if !film.directors.isEmpty {
                        Text("Directed by \(Text(film.directors.formatted(.list(type: .and))).foregroundStyle(LetterboxdTheme.title))")
                            .font(.system(size: 13))
                            .lineLimit(2)
                    }
                    if !facts.isEmpty {
                        Text(facts).font(.system(size: 12)).foregroundStyle(LetterboxdTheme.muted).lineLimit(1)
                    }
                    if let rating = film.rating {
                        AverageRating(rating: rating, ratings: film.ratings).padding(.vertical, 2)
                    }
                    if let tagline = film.tagline {
                        Text(tagline.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(LetterboxdTheme.label)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !film.synopsis.isEmpty {
                        Text(film.synopsis)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !film.cast.isEmpty {
                        Text("Starring \(film.cast.formatted(.list(type: .and)))")
                            .font(.system(size: 12))
                            .foregroundStyle(LetterboxdTheme.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(LetterboxdCardView.padding)
        }
    }

    /// "116 mins · Thriller, Horror"
    private var facts: String {
        [film.runtime.map { "\($0) mins" }, film.genres.isEmpty ? nil : film.genres.prefix(3).joined(separator: ", ")]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ReviewCard: View {
    let review: LetterboxdReview
    let url: URL
    @State private var showsSpoilers = false

    /// Longer reviews scroll inside the card.
    private static let textHeight: CGFloat = 260
    private static let textFont = NSFont.systemFont(ofSize: 14)
    private static let lineSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpenButton(url: url) {
                HStack(alignment: .top, spacing: 14) {
                    Poster(url: review.poster, width: 70)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Avatar(url: review.avatar, size: 24)
                            Text("\(review.text.isEmpty ? "Diary entry by" : "Review by") \(Text(review.member).fontWeight(.semibold).foregroundStyle(LetterboxdTheme.title))")
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        FilmTitle(title: review.film, year: review.year, size: 19)
                        HStack(spacing: 8) {
                            if let rating = review.rating {
                                Stars(rating: rating, size: 15)
                            }
                            if review.liked {
                                Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(LetterboxdTheme.orange).accessibilityLabel("Liked")
                            }
                            if review.rewatch {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(LetterboxdTheme.label).accessibilityLabel("Rewatch")
                            }
                        }
                        if let watched = review.watched {
                            Text("\(review.rewatch ? "Rewatched" : "Watched") \(watched)").font(.system(size: 12)).foregroundStyle(LetterboxdTheme.muted)
                        }
                    }
                }
            }
            if !review.text.isEmpty {
                if review.hasSpoilers, !showsSpoilers {
                    Button { showsSpoilers = true } label: {
                        // Bars in place of the words, which never draw.
                        reviewText
                            .redacted(reason: .placeholder)
                            .frame(maxHeight: 90, alignment: .top)
                            .clipped()
                            .overlay {
                                Label("This review may contain spoilers. Show it", systemImage: "eye.slash")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(LetterboxdTheme.title)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(LetterboxdTheme.raised, in: Capsule())
                            }
                            .contentShape(Rectangle())
                    }
                    .help("Show the review")
                } else if Self.height(of: review.text) > Self.textHeight {
                    ScrollView { reviewText.padding(.trailing, 8) }
                        .frame(height: Self.textHeight)
                        .scrollIndicators(.visible)
                } else {
                    OpenButton(url: url) { reviewText }
                }
            }
            if let likes = review.likes, likes > 0 {
                Label(likes == 1 ? "1 like" : "\(likes.formatted()) likes", systemImage: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(LetterboxdTheme.muted)
            }
        }
        .padding(LetterboxdCardView.padding)
    }

    private var reviewText: some View {
        Text(review.text)
            .font(Font(Self.textFont))
            .lineSpacing(Self.lineSpacing)
            .foregroundStyle(LetterboxdTheme.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// How tall the review's text is across the card.
    private static func height(of text: String) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let width = LetterboxdCardView.width - 2 * LetterboxdCardView.padding
        return (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                               attributes: [.font: textFont, .paragraphStyle: style]).height
    }
}

private struct PersonCard: View {
    let person: LetterboxdPerson
    let url: URL

    var body: some View {
        OpenButton(url: url) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    if let photo = person.photo {
                        Picture(url: photo, size: CGSize(width: 96, height: 144))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(person.role.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(LetterboxdTheme.label)
                        Text(person.name)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(LetterboxdTheme.title)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !person.otherRoles.isEmpty {
                            Text("Also \(person.otherRoles.map { "\($0.name.lowercased()) (\($0.films))" }.formatted(.list(type: .and)))")
                                .font(.system(size: 12))
                                .foregroundStyle(LetterboxdTheme.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !person.bio.isEmpty {
                            Text(person.bio)
                                .font(.system(size: 13))
                                .lineSpacing(2)
                                .lineLimit(7)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                PosterRow(films: person.films)
            }
            .padding(LetterboxdCardView.padding)
        }
    }
}

private struct ListCard: View {
    let list: LetterboxdList
    let url: URL

    private static let bannerHeight: CGFloat = 140

    var body: some View {
        OpenButton(url: url) {
            VStack(alignment: .leading, spacing: 0) {
                if let banner = list.banner {
                    // Letterboxd fades its backdrops into the page.
                    Picture(url: banner, size: CGSize(width: LetterboxdCardView.width, height: Self.bannerHeight), cornerRadius: 0)
                        .overlay {
                            LinearGradient(colors: [.clear, LetterboxdTheme.background], startPoint: .center, endPoint: .bottom)
                        }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Avatar(url: list.avatar, size: 20)
                        Text("List by \(Text(list.owner).fontWeight(.semibold).foregroundStyle(LetterboxdTheme.title))")
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    Text(list.title)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(LetterboxdTheme.title)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !facts.isEmpty {
                        Text(facts).font(.system(size: 12)).foregroundStyle(LetterboxdTheme.muted).lineLimit(1)
                    }
                    if !list.notes.isEmpty {
                        Text(list.notes)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PosterRow(films: list.films).padding(.top, 4)
                }
                .padding(LetterboxdCardView.padding)
            }
        }
    }

    /// "13 films · Ranked · 497 likes"
    private var facts: String {
        [list.count.map { $0 == 1 ? "1 film" : "\($0.formatted()) films" },
         list.isRanked ? "Ranked" : nil,
         list.likes.flatMap { $0 == 0 ? nil : $0 == 1 ? "1 like" : "\($0.formatted()) likes" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Parts

/// "Us 2019": the title in Letterboxd's serif, the year beside it.
private struct FilmTitle: View {
    let title: String
    let year: String?
    let size: CGFloat

    var body: some View {
        Text("\(Text(title).font(.system(size: size, weight: .bold, design: .serif)).foregroundStyle(LetterboxdTheme.title))\(year.map { Text(verbatim: "  \($0)").font(.system(size: size * 0.7)).foregroundStyle(LetterboxdTheme.muted) } ?? Text(verbatim: ""))")
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A member's rating: green stars, with a half.
private struct Stars: View {
    let rating: Double
    let size: CGFloat

    var body: some View {
        Text(verbatim: String(repeating: "★", count: Int(rating)) + (rating.truncatingRemainder(dividingBy: 1) >= 0.5 ? "½" : ""))
            .font(.system(size: size))
            .foregroundStyle(LetterboxdTheme.stars)
            .accessibilityLabel(rating == 1 ? "1 star" : "\(rating.formatted()) stars")
    }
}

/// The average of everyone's ratings: "★ 3.6 from 2.6M ratings".
private struct AverageRating: View {
    let rating: Double
    let ratings: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(LetterboxdTheme.stars)
            Text(rating.formatted(.number.precision(.fractionLength(1))))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LetterboxdTheme.title)
            if let ratings {
                Text("from \(ratings.formatted(.number.notation(.compactName))) \(ratings == 1 ? "rating" : "ratings")")
                    .font(.system(size: 12))
                    .foregroundStyle(LetterboxdTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row of posters across the card, each named in its tooltip.
private struct PosterRow: View {
    let films: [LetterboxdPoster]

    private static let count = 5
    private static let spacing: CGFloat = 8

    var body: some View {
        let shown = films.filter { $0.image != nil }.prefix(Self.count)
        if !shown.isEmpty {
            let width = ((LetterboxdCardView.width - 2 * LetterboxdCardView.padding - Self.spacing * CGFloat(Self.count - 1)) / CGFloat(Self.count)).rounded(.down)
            HStack(spacing: Self.spacing) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, film in
                    Poster(url: film.image, width: width).help(film.name)
                }
            }
        }
    }
}

/// A poster at 2:3, framed as Letterboxd frames them.
private struct Poster: View {
    let url: URL?
    let width: CGFloat

    var body: some View {
        Picture(url: url, size: CGSize(width: width, height: (width * 1.5).rounded()))
    }
}

private struct Picture: View {
    let url: URL?
    let size: CGSize
    var cornerRadius: CGFloat = 4

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            LetterboxdTheme.raised
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            if cornerRadius > 0 {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.white.opacity(0.12))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Avatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            LetterboxdTheme.raised
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Letterboxd's colors. The site is dark only.
enum LetterboxdTheme {
    static let background = color(0x14181C)
    static let raised = color(0x2C3440)
    static let title = color(0xFFFFFF)
    static let text = color(0xBBCCDD)
    static let body = color(0x99AABB)
    static let label = color(0x8899AA)
    static let muted = color(0x778899)
    static let stars = color(0x00C030)
    static let orange = color(0xFF8000)

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

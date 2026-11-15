import Foundation
import Testing
@testable import HoverEnhance

/// The parsers against the real sites, which change their pages without notice: the other tests would
/// go on passing while the cards stopped appearing. Off by default, as it needs the network and asks
/// real servers: `make live`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HOVERENHANCE_LIVE"] != nil), .serialized)
struct LiveLetterboxdTests {
    private let fetcher = MediaFetcher()

    private func card(_ ref: LetterboxdRef) async -> LetterboxdCard? {
        guard case .found(let media) = await fetcher.lookUp(.letterboxd(ref)), case .letterboxd(let card) = media.items.first else { return nil }
        return card
    }

    @Test func aFilm() async {
        guard case .film(let film) = await card(.film("parasite-2019")) else { Issue.record("no film card"); return }
        #expect(film.title == "Parasite")
        #expect(film.year == "2019")
        #expect(film.directors == ["Bong Joon Ho"])
        #expect(film.runtime != nil)
        #expect(film.rating != nil)
        #expect((film.ratings ?? 0) > 1_000_000)
        #expect((film.reviews ?? 0) > 100_000)
        #expect(film.tagline != nil)
        #expect(!film.synopsis.isEmpty)
        #expect(!film.cast.isEmpty)
        #expect(film.poster != nil)
    }

    @Test func aFilmByItsIMDbAndTMDBNumbers() async {
        for path in ["imdb/tt6751668", "tmdb/496243"] {
            guard case .film(let film) = await card(.external(path)) else { Issue.record("no film card for \(path)"); continue }
            #expect(film.title == "Parasite")
        }
    }

    @Test func aReview() async {
        guard case .review(let review) = await card(.review(member: "davidehrlich", film: "parasite-2019", viewing: nil)) else {
            Issue.record("no review card"); return
        }
        #expect(!review.member.isEmpty)
        #expect(review.avatar != nil)
        #expect(review.film == "Parasite")
        #expect(review.rating != nil)
        #expect(review.watched != nil)
        #expect(!review.text.isEmpty)
        #expect((review.likes ?? 0) > 0)
        #expect(review.poster != nil)
    }

    @Test func aPerson() async {
        guard case .person(let person) = await card(.person(role: "director", slug: "bong-joon-ho")) else { Issue.record("no person card"); return }
        #expect(person.name == "Bong Joon Ho")
        #expect(person.photo != nil)
        #expect(!person.bio.isEmpty)
        #expect(!person.otherRoles.isEmpty)
        #expect(person.films.count == 5)
        #expect(person.films.allSatisfy { $0.image != nil })
    }

    @Test func aList() async {
        guard case .list(let list) = await card(.list(member: "davidehrlich", slug: "christopher-nolan-films-ranked")) else {
            Issue.record("no list card"); return
        }
        #expect(!list.title.isEmpty)
        #expect(!list.owner.isEmpty)
        #expect(list.avatar != nil)
        #expect((list.count ?? 0) > 5)
        #expect((list.likes ?? 0) > 0)
        #expect(list.films.count == 5)
    }

    /// Through the offscreen web view, as Cloudflare lets nothing else read a profile.
    @Test func aMember() async {
        guard case .member(let member) = await card(.member("davidehrlich")) else { Issue.record("no member card"); return }
        #expect(member.username == "davidehrlich")
        #expect(member.avatar != nil)
        #expect(!member.bio.isEmpty)
        #expect(member.stats.map(\.name) == ["Films", "This year", "Lists", "Following", "Followers"])
        #expect(member.favorites.count == 4)
        #expect(member.favorites.allSatisfy { $0.image != nil })
    }

    @Test func aMemberWhoIsntThere() async {
        #expect(await fetcher.lookUp(.letterboxd(.member("nosuchmember12345xyzq"))) == .nothing)
    }
}

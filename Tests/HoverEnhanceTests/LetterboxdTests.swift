import Foundation
import Testing
@testable import HoverEnhance

struct LetterboxdLinkTests {
    private func ref(_ string: String) -> LetterboxdRef? {
        Letterboxd.ref(fromLink: URL(string: string)!)
    }

    @Test func filmsReviewsPeopleAndLists() {
        #expect(ref("https://letterboxd.com/film/us-2019/") == .film("us-2019"))
        #expect(ref("https://www.letterboxd.com/film/us-2019") == .film("us-2019"))
        #expect(ref("https://letterboxd.com/maddmattw/film/us-2019/") == .review(member: "maddmattw", film: "us-2019", viewing: nil))
        #expect(ref("https://letterboxd.com/Madd_Matt/film/us-2019/2/#comments") == .review(member: "Madd_Matt", film: "us-2019", viewing: 2))
        #expect(ref("https://letterboxd.com/director/jordan-peele/") == .person(role: "director", slug: "jordan-peele"))
        #expect(ref("https://letterboxd.com/actor/lupita-nyongo/") == .person(role: "actor", slug: "lupita-nyongo"))
        #expect(ref("https://letterboxd.com/davidehrlich/list/christopher-nolan-films-ranked/") == .list(member: "davidehrlich", slug: "christopher-nolan-films-ranked"))
        #expect(ref("https://boxd.it/FtSXN") == .short("FtSXN"))
    }

    @Test func otherPagesHaveNoCard() {
        #expect(ref("https://letterboxd.com/") == nil)
        #expect(ref("https://letterboxd.com/maddmattw/") == nil, "profiles are behind a bot check")
        #expect(ref("https://letterboxd.com/film/us-2019/crew/") == nil, "a film's tabs are the film's page")
        #expect(ref("https://letterboxd.com/maddmattw/film/us-2019/likes/") == nil)
        #expect(ref("https://letterboxd.com/studio/universal-pictures/") == nil)
        #expect(ref("https://letterboxd.com/films/year/2019/") == nil)
        #expect(ref("https://letterboxd.com/film/Us_2019/") == nil)
        #expect(ref("https://letterboxd.com.example/film/us-2019/") == nil)
        #expect(ref("https://boxd.it/") == nil)
        #expect(ref("https://boxd.it/a/b") == nil)
    }

    @Test func pageURLs() {
        #expect(LetterboxdRef.review(member: "maddmattw", film: "us-2019", viewing: 2).pageURL == URL(string: "https://letterboxd.com/maddmattw/film/us-2019/2/"))
        #expect(LetterboxdRef.list(member: "a", slug: "b").pageURL == URL(string: "https://letterboxd.com/a/list/b/"))
        #expect(LetterboxdRef.short("FtSXN").pageURL == URL(string: "https://boxd.it/FtSXN"))
    }
}

struct LetterboxdPageTests {
    private let film = """
    <html><head><meta property="og:type" content="video.movie"></head><body>
    <div class="details"><h1 class="headline-1 primaryname"><span class="name js-widont prettify">Us</span></h1>
    <div class="productioninfo"><span class="releasedate"><a href="/films/year/2019/">2019</a></span></div></div>
    <h4 class="tagline">Watch yourself.</h4>
    <script type="application/ld+json">
    /* <![CDATA[ */
    {"image":"https://a.ltrbxd.com/resized/film-poster/3/9/0/5/2/0/390520-us-0-600-0-900-crop.jpg?v=968884c876","@type":"Movie",
     "director":[{"@type":"Person","name":"Jordan Peele","sameAs":"https://letterboxd.com/director/jordan-peele/"}],
     "description":"A family\\u2019s beach trip turns strange.","url":"https://letterboxd.com/film/us-2019/","duration":"PT1H56M",
     "actor":[{"name":"Lupita Nyong'o"},{"name":"Winston Duke"},{"name":"Elisabeth Moss"},{"name":"Tim Heidecker"},{"name":"Evan Alex"}],
     "dateCreated":"2019-03-08","name":"Us","genre":["Thriller","Horror"],
     "aggregateRating":{"bestRating":5,"reviewCount":340556,"@type":"AggregateRating","ratingValue":3.63,"ratingCount":2559990,"worstRating":0.5}}
    /* ]]> */
    </script></body></html>
    """

    @Test func aFilm() throws {
        let card = Letterboxd.card(inPage: film, at: URL(string: "https://letterboxd.com/film/us-2019/")!)
        guard case .film(let film) = card else { Issue.record("not a film: \(String(describing: card))"); return }
        #expect(film.title == "Us")
        #expect(film.year == "2019")
        #expect(film.directors == ["Jordan Peele"])
        #expect(film.runtime == 116)
        #expect(film.genres == ["Thriller", "Horror"])
        #expect(film.rating == 3.63)
        #expect(film.ratings == 2559990)
        #expect(film.tagline == "Watch yourself.")
        #expect(film.synopsis == "A family’s beach trip turns strange.")
        #expect(film.cast == ["Lupita Nyong'o", "Winston Duke", "Elisabeth Moss", "Tim Heidecker"])
        #expect(film.poster == URL(string: "https://a.ltrbxd.com/resized/film-poster/3/9/0/5/2/0/390520-us-0-600-0-900-crop.jpg?v=968884c876"))
    }

    @Test func filmsTooLittleRatedHaveNoAverage() throws {
        let page = film.replacing(/,\s*"aggregateRating":\{[^}]*\}/, with: "")
        guard case .film(let film) = Letterboxd.card(inPage: page, at: URL(string: "https://letterboxd.com/film/us-2019/")!) else {
            Issue.record("not a film"); return
        }
        #expect(film.rating == nil)
        #expect(film.ratings == nil)
    }

    @Test func runtimes() {
        #expect(Letterboxd.minutes("PT1H56M") == 116)
        #expect(Letterboxd.minutes("PT2H") == 120)
        #expect(Letterboxd.minutes("PT45M") == 45)
        #expect(Letterboxd.minutes("PT") == nil)
        #expect(Letterboxd.minutes("1H") == nil)
    }

    /// A review page, trimmed: the reviewer, the film, their rating, like and date, the review, and its likes.
    private func review(reactions: String, date: String, description: String = "A short review.", body: String) -> String {
        """
        <html><head><meta name="description" content="\(description)">
        <meta property="og:type" content="letterboxd:review"><meta property="og:description" content="\(description)">
        <meta name="twitter:data1" content="maddmattw"></head><body>
        <section class="film-viewing-info-wrapper"><header class="page-header overflow person-header">
        <div class="person-summary -inline"><a class="avatar -a24" href="/maddmattw/"><img src="https://a.ltrbxd.com/resized/avatar/upload/avtr-0-48-0-48-crop.jpg?v=1" alt="maddmattw" width="24" height="24" /></a>
        <h1 class="title-4"><small class="context">Review by</small> <a href="/maddmattw/" class="name"> <span>Madd Matt W</span> <span class="badge -pro -small">Pro</span></a></h1></div></header>
        <div class="inline-production-masthead -film -full -linked "><div class="topline"><h2 class="primaryname prettify"><a href="/film/us-2019/">Us</a></h2><span class="releasedate"><a href="/films/year/2019/">2019</a></span></div></div>
        <div class="content-reactions-strip -viewing -single">\(reactions)</div>
        <div><p class="view-date">\(date)</p></div></section>
        <div class="review"><div class="body-text -prose -reset -hero"><div class="">
        <div class="js-review-body" lang="en" data-is-translatable="true">\(body)</div></div></div></div>
        <div class="viewing-actions"><p class="like-link-target react-component review-like" data-component-class="LikeComponent" data-format="count" data-count="2858" data-owner="maddmattw"></p></div>
        <form><div class="rating"><svg class="glyph -rating" aria-label="★★★★★"><title>★★★★★</title></svg></div></form>
        </body></html>
        """
    }

    private let fourAndAHalf = #"<span class="inline-symbol inline-rating"><svg xmlns="http://www.w3.org/2000/svg" role="graphics-symbol" class="glyph -rating" width="76" height="15" viewBox="0 0 76 15" aria-label="★★★★½"> <title>★★★★½</title></svg></span>"#
    private let liked = #"<span class="inline-symbol"><svg xmlns="http://www.w3.org/2000/svg" role="graphics-symbol" class="glyph inline-liked -like" width="14" height="12" viewBox="0 0 14 12" aria-label="Liked"> <title>Liked</title></svg></span>"#
    private let watched = #"Watched <a href="/maddmattw/diary/for/2026/10/08/">08</a> <a href="/maddmattw/diary/for/2026/10/">Oct</a> <a href="/maddmattw/diary/for/2026/">2026</a>"#
    private let reviewURL = URL(string: "https://letterboxd.com/maddmattw/film/us-2019/")!

    @Test func aReview() throws {
        let page = review(reactions: fourAndAHalf + liked, date: watched,
                          body: "<p>Scarier the second time &amp; funnier too.</p><p>That score!<br>Those scissors.</p>")
        guard case .review(let review) = Letterboxd.card(inPage: page, at: reviewURL) else { Issue.record("not a review"); return }
        #expect(review.member == "Madd Matt W")
        #expect(review.avatar == URL(string: "https://a.ltrbxd.com/resized/avatar/upload/avtr-0-48-0-48-crop.jpg?v=1"))
        #expect(review.film == "Us")
        #expect(review.filmSlug == "us-2019")
        #expect(review.year == "2019")
        // Not the five stars of the rating form further down.
        #expect(review.rating == 4.5)
        #expect(review.liked)
        #expect(!review.rewatch)
        #expect(review.watched == "8 Oct 2026")
        #expect(review.text == "Scarier the second time & funnier too.\n\nThat score!\nThose scissors.")
        #expect(!review.hasSpoilers)
        #expect(review.likes == 2858)
        #expect(review.url == reviewURL)
    }

    @Test func rewatchesAndSpoilers() throws {
        let page = review(reactions: fourAndAHalf, date: watched.replacingOccurrences(of: "Watched", with: "Rewatched"),
                          description: "This review may contain spoilers. Visit the page to bypass this warning and read the review.",
                          body: "<p>The twist.</p>")
        guard case .review(let review) = Letterboxd.card(inPage: page, at: reviewURL) else { Issue.record("not a review"); return }
        #expect(review.rewatch)
        #expect(review.hasSpoilers)
        #expect(!review.liked)
    }

    @Test func diaryEntriesHaveNoText() throws {
        let page = review(reactions: "", date: watched.replacingOccurrences(of: "Watched ", with: ""), body: "")
            .replacingOccurrences(of: #"<div class="js-review-body" lang="en" data-is-translatable="true"></div>"#, with: "")
        guard case .review(let review) = Letterboxd.card(inPage: page, at: reviewURL) else { Issue.record("not a review"); return }
        #expect(review.text.isEmpty)
        #expect(review.rating == nil)
        #expect(review.watched == "8 Oct 2026")
    }

    @Test func aPerson() throws {
        let page = """
        <html><head><meta property="og:title" content="Films directed by Jordan Peele"></head><body>
        <figure class="contributor-image"><span class="media"><img src="https://s.ltrbxd.com/static/img/empty.png" class="js-tmdb-person" data-image="https://image.tmdb.org/t/p/w500/kFUKn5g3ebpyZ3CSZZZo2HFWRNQ.jpg" data-tmdb-id="291263" /></span></figure>
        <div class="title"><h1 class="contextual-title prettify"> <span class="context title-all-caps"> Films directed by </span> <span class="name">Jordan Peele</span> </h1></div>
        <div id="content-nav"><section class="smenu-wrapper"><div class="smenu js-smenu"><label>Director</label><ul class="smenu-menu">
        <li><a href="/actor/jordan-peele/" class="item"> Actor <small>29</small> </a></li>
        <li><a href="/executive-producer/jordan-peele/" class="item"> Executive Producer <small>1,010</small> </a></li>
        </ul></div></section></div>
        <div class="bio"><div class="panel-text body-text -reset js-tmdb-bio"><p>An American filmmaker.</p><p>Known for horror.</p></div></div>
        <div class="react-component" data-component-class="LazyPoster" data-item-name="Get Out (2017)" data-item-slug="get-out-2017" data-item-link="/film/get-out-2017/"></div>
        <div class="react-component" data-component-class="LazyPoster" data-item-name="Us (2019)" data-item-slug="us-2019" data-item-link="/film/us-2019/"></div>
        </body></html>
        """
        guard case .person(let person) = Letterboxd.card(inPage: page, at: URL(string: "https://letterboxd.com/director/jordan-peele/")!) else {
            Issue.record("not a person"); return
        }
        #expect(person.name == "Jordan Peele")
        #expect(person.role == "Director")
        #expect(person.photo == URL(string: "https://image.tmdb.org/t/p/w500/kFUKn5g3ebpyZ3CSZZZo2HFWRNQ.jpg"))
        #expect(person.bio == "An American filmmaker.\n\nKnown for horror.")
        #expect(person.otherRoles == [.init(name: "Actor", films: 29), .init(name: "Executive Producer", films: 1010)])
        #expect(person.films == [LetterboxdPoster(slug: "get-out-2017", name: "Get Out (2017)"), LetterboxdPoster(slug: "us-2019", name: "Us (2019)")])
    }

    @Test func aList() throws {
        let posters = (1...7).map { #"<li class="posteritem numbered-list-item"><div class="react-component" data-component-class="LazyPoster" data-item-name="Film \#($0)" data-item-slug="film-\#($0)"></div></li>"# }
        let page = """
        <html><head><meta name="description" content="A list of 1,013 films compiled on Letterboxd, including Film 1.">
        <meta property="og:type" content="letterboxd:list"><meta property="og:title" content="NOLAN, RANKED">
        <meta property="og:description" content="Every film, from &lsquo;Following&rsquo; on.">
        <meta property="og:image" content="https://a.ltrbxd.com/resized/sm/upload/dunkirk-1200-1200-675-675-crop-000000.jpg?v=5"></head><body>
        <div class="person-summary -inline"><a class="avatar -a24" href="/davidehrlich/"><img src="https://a.ltrbxd.com/resized/avatar/a-0-48-0-48-crop.jpg?v=e" alt="davidehrlich" /></a>
        <h1 class="title-4"><small class="context">List by</small> <a href="/davidehrlich/" class="name"> <span>davidehrlich</span></a></h1></div>
        <div data-like-count="497"></div><ul class="poster-list">\(posters.joined())</ul></body></html>
        """
        guard case .list(let list) = Letterboxd.card(inPage: page, at: URL(string: "https://letterboxd.com/davidehrlich/list/nolan/")!) else {
            Issue.record("not a list"); return
        }
        #expect(list.title == "NOLAN, RANKED")
        #expect(list.owner == "davidehrlich")
        #expect(list.notes == "Every film, from ‘Following’ on.")
        #expect(list.banner == URL(string: "https://a.ltrbxd.com/resized/sm/upload/dunkirk-1200-1200-675-675-crop-000000.jpg?v=5"))
        #expect(list.count == 1013)
        #expect(list.likes == 497)
        #expect(list.isRanked)
        #expect(list.films.map(\.slug) == ["film-1", "film-2", "film-3", "film-4", "film-5"])
    }

    @Test func pagesOfOtherKindsHaveNoCard() {
        // A short link that led somewhere without a card, and a page that isn't what its address says.
        #expect(Letterboxd.card(inPage: film, at: URL(string: "https://letterboxd.com/maddmattw/")!) == nil)
        #expect(Letterboxd.card(inPage: film, at: URL(string: "https://letterboxd.com/maddmattw/film/us-2019/")!) == nil)
        #expect(Letterboxd.card(inPage: "<html>Just a moment...</html>", at: URL(string: "https://letterboxd.com/film/us-2019/")!) == nil)
    }

    @Test func posters() {
        let json = #"{"url":"https://a.ltrbxd.com/resized/film-poster/us-0-230-0-345-crop.jpg?v=9","url2x":"https://a.ltrbxd.com/resized/film-poster/us-0-460-0-690-crop.jpg?v=9","shouldObfuscate":false}"#
        #expect(Letterboxd.poster(Data(json.utf8)) == URL(string: "https://a.ltrbxd.com/resized/film-poster/us-0-460-0-690-crop.jpg?v=9"))
        // Letterboxd hides adult films' posters unless asked.
        #expect(Letterboxd.poster(Data(json.replacingOccurrences(of: "false", with: "true").utf8)) == nil)
        #expect(Letterboxd.poster(Data(#"{"url":"http://192.168.1.1/poster.jpg"}"#.utf8)) == nil)
        #expect(Letterboxd.posterURL(film: "us-2019") == URL(string: "https://letterboxd.com/film/us-2019/poster/std/230/"))
        #expect(Letterboxd.posterURL(film: "../../x") == nil)
    }

    @Test func stars() {
        #expect(Letterboxd.stars("★★★★½") == 4.5)
        #expect(Letterboxd.stars("½") == 0.5)
        #expect(Letterboxd.stars("★★★★★") == 5)
    }

    @Test func htmlText() {
        #expect(HTMLText.plain("<p>One &amp; two</p>\n<p>Three<br/>four &#039;five&#x27; &lrm;</p>") == "One & two\n\nThree\nfour 'five'")
        #expect(HTMLText.decode("&unknown; &#128512;") == "&unknown; 😀")
    }
}

struct LetterboxdHoverRuleTests {
    private func info(link: String, image: String? = nil, page: String = "https://letterboxd.com/") -> HoverInfo {
        var info = HoverInfo(pid: 1, appKind: .browser)
        info.pageURL = URL(string: page)
        info.linkURL = URL(string: link)
        info.imageURL = image.flatMap(URL.init(string:))
        return info
    }

    private let poster = "https://a.ltrbxd.com/resized/film-poster/3/9/0/5/2/0/390520-us-0-150-0-225-crop.jpg?v=1"

    @Test func postersGetTheirCardInsteadOfALargerPoster() {
        // "New from friends" links each poster to the friend's review.
        #expect(MediaResolver.source(for: info(link: "https://letterboxd.com/maddmattw/film/us-2019/", image: poster))
            == .letterboxd(.review(member: "maddmattw", film: "us-2019", viewing: nil)))
        #expect(MediaResolver.source(for: info(link: "https://letterboxd.com/film/us-2019/", image: poster, page: "https://www.reddit.com/r/movies/"))
            == .letterboxd(.film("us-2019")))
    }

    @Test func notALinkToThePageItself() {
        let source = MediaResolver.source(for: info(link: "https://letterboxd.com/film/us-2019/", image: poster, page: "https://letterboxd.com/film/us-2019/"))
        #expect(source == .images([URL(string: "https://a.ltrbxd.com/resized/film-poster/3/9/0/5/2/0/390520-us-0-1000-0-1500-crop.jpg?v=1")!, URL(string: poster)!]))
    }

    @Test func aSecondLookThatFindsThePostersLinkReplacesItsZoom() {
        // Chromium can put the poster in its accessibility tree before the link over it: the first look
        // finds only the image, and a second, the link.
        let zoom = MediaSource.images([URL(string: poster)!])
        let card = MediaSource.letterboxd(.review(member: "maddmattw", film: "us-2019", viewing: nil))
        #expect(card.replaces(onSecondLook: zoom))
        #expect(MediaSource.redditGallery(id: "abc").replaces(onSecondLook: zoom))
        // Nothing replaces a card or a video, and an image doesn't replace an image.
        #expect(!zoom.replaces(onSecondLook: card))
        #expect(!card.replaces(onSecondLook: .letterboxd(.film("us-2019"))))
        #expect(!MediaSource.images([URL(string: "https://example.com/other.jpg")!]).replaces(onSecondLook: zoom))
        #expect(!card.replaces(onSecondLook: .video(URL(string: "https://example.com/clip.mp4")!)))
    }

    @Test func withCardsOffPostersAreEnlargedAsBefore() {
        let source = MediaResolver.source(for: info(link: "https://letterboxd.com/maddmattw/film/us-2019/", image: poster), cards: false)
        #expect(source == .images([URL(string: "https://a.ltrbxd.com/resized/film-poster/3/9/0/5/2/0/390520-us-0-1000-0-1500-crop.jpg?v=1")!, URL(string: poster)!]))
        #expect(!PreviewFilter(cards: false).allows(.letterboxd(.film("us-2019"))))
        #expect(!PreviewFilter(disabledSites: [.letterboxd]).allows(.letterboxd(.short("gnV6"))))
        #expect(MediaSource.letterboxd(.short("gnV6")).site == .letterboxd)
    }
}

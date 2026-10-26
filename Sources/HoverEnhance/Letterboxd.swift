import Foundation

/// A Letterboxd page a link points at.
enum LetterboxdRef: Sendable, Hashable {
    /// /film/<slug>/
    case film(String)
    /// /<member>/film/<slug>/, a member's review or diary entry; later viewings of the same film are numbered.
    case review(member: String, film: String, viewing: Int?)
    /// /<role>/<slug>/, as /director/jordan-peele/: someone's films in one role.
    case person(role: String, slug: String)
    /// /<member>/list/<slug>/
    case list(member: String, slug: String)
    /// boxd.it/<code>, the short links Letterboxd shares, to any of the above.
    case short(String)

    var pageURL: URL {
        let path = switch self {
        case .film(let slug): "film/\(slug)/"
        case .review(let member, let film, let viewing): "\(member)/film/\(film)/" + (viewing.map { "\($0)/" } ?? "")
        case .person(let role, let slug): "\(role)/\(slug)/"
        case .list(let member, let slug): "\(member)/list/\(slug)/"
        case .short(let code): code
        }
        return URL(string: (self.isShort ? "https://boxd.it/" : "https://letterboxd.com/") + path)!
    }

    private var isShort: Bool {
        if case .short = self { true } else { false }
    }
}

/// A film, as its page describes it.
struct LetterboxdFilm: Sendable, Equatable {
    let title: String
    let year: String?
    let directors: [String]
    /// Minutes.
    let runtime: Int?
    let genres: [String]
    /// Letterboxd's weighted average, out of five, and how many ratings it's from. Missing for films too
    /// little rated to have one.
    let rating: Double?
    let ratings: Int?
    let tagline: String?
    let synopsis: String
    let cast: [String]
    let poster: URL?
    let url: URL
}

/// A member's review, or a diary entry without one.
struct LetterboxdReview: Sendable, Equatable {
    /// The member's display name.
    let member: String
    let avatar: URL?
    let film: String
    let filmSlug: String
    let year: String?
    /// Out of five, in halves.
    let rating: Double?
    let liked: Bool
    let rewatch: Bool
    /// As the page writes it: "18 Mar 2019".
    let watched: String?
    /// Paragraphs, as plain text. Empty for a diary entry.
    let text: String
    let hasSpoilers: Bool
    let likes: Int?
    var poster: URL? = nil
    let url: URL
}

/// Someone's films in one role, with what Letterboxd knows of them from TMDB.
struct LetterboxdPerson: Sendable, Equatable {
    let name: String
    /// "Director", "Actor".
    let role: String
    let photo: URL?
    let bio: String
    /// Their other roles, with how many films each.
    let otherRoles: [Role]
    /// In the page's order, most popular first.
    var films: [LetterboxdPoster]
    let url: URL

    struct Role: Sendable, Equatable {
        let name: String
        let films: Int
    }
}

/// A member's list.
struct LetterboxdList: Sendable, Equatable {
    let title: String
    let owner: String
    let avatar: URL?
    let notes: String
    /// A still from its first film, as its page's preview image.
    let banner: URL?
    let count: Int?
    let likes: Int?
    let isRanked: Bool
    /// Its first films, in order.
    var films: [LetterboxdPoster]
    let url: URL
}

/// A film in a row of posters: its slug, which finds the poster, and its name.
struct LetterboxdPoster: Sendable, Equatable {
    let slug: String
    let name: String
    var image: URL? = nil
}

enum LetterboxdCard: Sendable, Equatable {
    case film(LetterboxdFilm)
    case review(LetterboxdReview)
    case person(LetterboxdPerson)
    case list(LetterboxdList)

    var url: URL {
        switch self {
        case .film(let film): film.url
        case .review(let review): review.url
        case .person(let person): person.url
        case .list(let list): list.url
        }
    }
}

enum Letterboxd {
    static func isLetterboxd(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "letterboxd.com" || host == "www.letterboxd.com"
    }

    /// The paths that list someone's films in a role. Studios, countries, and the like have pages too, but
    /// no one to describe.
    static let roles: Set<String> = [
        "actor", "director", "co-director", "producer", "executive-producer", "writer", "original-writer", "story",
        "editor", "cinematography", "composer", "songs", "casting", "production-design", "art-direction",
        "set-decoration", "costume-design", "makeup", "hairstyling", "visual-effects", "special-effects", "sound",
        "stunts", "choreography", "title-design", "camera-operator", "lighting", "additional-directing",
    ]

    static func ref(fromLink url: URL) -> LetterboxdRef? {
        guard ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host()?.lowercased() else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        if host == "boxd.it" {
            guard parts.count == 1, (1...12).contains(parts[0].count), parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
            return .short(parts[0])
        }
        guard host == "letterboxd.com" || host == "www.letterboxd.com" else { return nil }
        switch parts.count {
        case 2 where parts[0] == "film" && isSlug(parts[1]):
            return .film(parts[1])
        case 2 where roles.contains(parts[0]) && isSlug(parts[1]):
            return .person(role: parts[0], slug: parts[1])
        case 3 where isMember(parts[0]) && parts[1] == "film" && isSlug(parts[2]):
            return .review(member: parts[0], film: parts[2], viewing: nil)
        case 4 where isMember(parts[0]) && parts[1] == "film" && isSlug(parts[2]) && SiteLinks.isNumericID(parts[3]) && parts[3].count <= 6:
            return .review(member: parts[0], film: parts[2], viewing: Int(parts[3]))
        case 3 where isMember(parts[0]) && parts[1] == "list" && isSlug(parts[2]):
            return .list(member: parts[0], slug: parts[2])
        default:
            return nil
        }
    }

    /// Lowercase letters, digits, and hyphens, as Letterboxd writes film, person, and list slugs.
    private static func isSlug(_ string: String) -> Bool {
        (1...200).contains(string.count) && string.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }

    private static func isMember(_ string: String) -> Bool {
        (1...40).contains(string.count) && string.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    // MARK: - Posters

    /// The poster Letterboxd's own pages ask for, at `width` and twice that: answered with JSON.
    static func posterURL(film slug: String, width: Int = 230) -> URL? {
        isSlug(slug) ? URL(string: "https://letterboxd.com/film/\(slug)/poster/std/\(width)/") : nil
    }

    /// The sharper of the two sizes. None for a poster Letterboxd hides by default, as for adult films.
    static func poster(_ data: Data) -> URL? {
        struct Poster: Decodable { let url: String?; let url2x: String?; let shouldObfuscate: Bool? }
        guard let poster = try? JSONDecoder().decode(Poster.self, from: data), poster.shouldObfuscate != true else { return nil }
        return (poster.url2x ?? poster.url).flatMap(URL.init(string:)).flatMap(webImage)
    }

    // MARK: - Pages

    /// The card for a page, by what it says it is. `url` is where the page came from, after any redirect.
    static func card(inPage html: String, at url: URL) -> LetterboxdCard? {
        switch ref(fromLink: url) {
        case .film: film(inPage: html, at: url).map(LetterboxdCard.film)
        case .review: review(inPage: html, at: url).map(LetterboxdCard.review)
        case .person(let role, _): person(inPage: html, role: role, at: url).map(LetterboxdCard.person)
        case .list: list(inPage: html, at: url).map(LetterboxdCard.list)
        case .short, nil: nil
        }
    }

    /// From the page's JSON-LD, which carries most of what the page shows, and its tagline.
    static func film(inPage html: String, at url: URL) -> LetterboxdFilm? {
        guard let json = html.firstMatch(of: /<script type="application\/ld\+json">\s*(?:\/\*.*?\*\/)?\s*(\{[\s\S]*?\})\s*(?:\/\*.*?\*\/)?\s*<\/script>/),
              let object = try? JSONSerialization.jsonObject(with: Data(json.1.utf8)) as? [String: Any],
              let title = object["name"] as? String else { return nil }
        func names(_ key: String) -> [String] {
            (object[key] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        }
        let rating = object["aggregateRating"] as? [String: Any]
        let year = html.firstMatch(of: /class="releasedate"><a href="\/films\/year\/(\d{4})\//).map { String($0.1) }
            ?? (object["dateCreated"] as? String).map { String($0.prefix(4)) }
        return LetterboxdFilm(
            title: HTMLText.decode(title),
            year: year,
            directors: names("director").map(HTMLText.decode),
            runtime: (object["duration"] as? String).flatMap(minutes),
            genres: object["genre"] as? [String] ?? [],
            rating: rating?["ratingValue"] as? Double,
            ratings: rating?["ratingCount"] as? Int,
            tagline: html.firstMatch(of: /<h4 class="tagline">([\s\S]*?)<\/h4>/).map { HTMLText.plain(String($0.1)) }.flatMap { $0.isEmpty ? nil : $0 },
            synopsis: HTMLText.decode(object["description"] as? String ?? ""),
            cast: Array(names("actor").prefix(4)).map(HTMLText.decode),
            poster: (object["image"] as? String).flatMap(URL.init(string:)).flatMap(webImage),
            url: url
        )
    }

    /// "PT1H56M" → 116.
    static func minutes(_ duration: String) -> Int? {
        guard let match = duration.wholeMatch(of: /PT(?:(\d+)H)?(?:(\d+)M)?/), match.1 != nil || match.2 != nil else { return nil }
        let total = (match.1.flatMap { Int($0) } ?? 0) * 60 + (match.2.flatMap { Int($0) } ?? 0)
        return total > 0 ? total : nil
    }

    static func review(inPage html: String, at url: URL) -> LetterboxdReview? {
        guard meta("og:type", in: html) == "letterboxd:review", let film = filmMasthead(in: html) else { return nil }
        // The reviewer's rating and like, and the date, sit between the film's name and the review; forms
        // elsewhere on the page draw every possible rating.
        let header = section(of: html, from: "content-reactions-strip", to: "</section>") ?? ""
        let date = header.firstMatch(of: /<p class="view-date">\s*(\w*)\s*<a[^>]*>(\d+)<\/a>\s*<a[^>]*>(\w+)<\/a>\s*<a[^>]*>(\d{4})<\/a>/)
        let body = html.firstMatch(of: /<div class="js-review-body"[^>]*>([\s\S]*?)<\/div>/).map { HTMLText.plain(String($0.1)) } ?? ""
        let likes = html.firstMatch(of: /<p class="[^"]*review-like"[^>]*>/).flatMap { $0.0.firstMatch(of: /data-count="(\d+)"/) }.flatMap { Int($0.1) }
        let (member, avatar) = owner(in: html)
        return LetterboxdReview(
            member: member ?? meta("twitter:data1", in: html) ?? url.pathComponents.dropFirst().first ?? "",
            avatar: avatar,
            film: film.title,
            filmSlug: film.slug,
            year: film.year,
            rating: header.firstMatch(of: /class="glyph -rating"[^>]*aria-label="([★½]+)"/).map { stars(String($0.1)) },
            liked: header.contains(#"aria-label="Liked""#),
            rewatch: date?.1 == "Rewatched",
            watched: date.map { "\(Int($0.2) ?? 0) \($0.3) \($0.4)" },
            text: body,
            // The page shows the review in full, but tells search engines and link previews to keep away.
            hasSpoilers: meta("og:description", in: html)?.hasPrefix("This review may contain spoilers") == true,
            likes: likes,
            url: url
        )
    }

    /// "★★★★½" → 4.5.
    static func stars(_ string: String) -> Double {
        Double(string.filter { $0 == "★" }.count) + (string.contains("½") ? 0.5 : 0)
    }

    static func person(inPage html: String, role: String, at url: URL) -> LetterboxdPerson? {
        guard let name = html.firstMatch(of: /<h1 class="contextual-title[^"]*">[\s\S]*?<span class="name">([^<]+)<\/span>/) else { return nil }
        // The menu of roles under the name lists the others with their counts; the one shown has none.
        let menu = section(of: html, from: #"id="content-nav""#, to: "</ul>") ?? ""
        let others = menu.matches(of: /<a href="\/([a-z-]+)\/[^"]*" class="item">\s*([^<]+?)\s*<small>([\d,]+)<\/small>/).compactMap { match -> LetterboxdPerson.Role? in
            guard roles.contains(String(match.1)), let count = Int(match.3.replacingOccurrences(of: ",", with: "")) else { return nil }
            return LetterboxdPerson.Role(name: HTMLText.decode(String(match.2)), films: count)
        }
        return LetterboxdPerson(
            name: HTMLText.decode(String(name.1)).trimmingCharacters(in: .whitespacesAndNewlines),
            role: roleName(role),
            photo: html.firstMatch(of: /class="js-tmdb-person" data-image="([^"]+)"/).flatMap { URL(string: String($0.1)) }.flatMap(webImage),
            bio: html.firstMatch(of: /js-tmdb-bio">([\s\S]*?)<\/div>/).map { HTMLText.plain(String($0.1)) } ?? "",
            otherRoles: others,
            films: posters(in: html),
            url: url
        )
    }

    /// "executive-producer" → "Executive Producer".
    static func roleName(_ path: String) -> String {
        path.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func list(inPage html: String, at url: URL) -> LetterboxdList? {
        guard meta("og:type", in: html) == "letterboxd:list", let title = meta("og:title", in: html) else { return nil }
        let (owner, avatar) = owner(in: html)
        // "A list of 13 films compiled on Letterboxd, including…"
        let count = meta("description", named: true, in: html)?.firstMatch(of: /^A list of ([\d,]+) films?/)
            .flatMap { Int($0.1.replacingOccurrences(of: ",", with: "")) }
        let banner = meta("og:image", in: html).flatMap(URL.init(string:)).flatMap(webImage)
        return LetterboxdList(
            title: title,
            owner: owner ?? "",
            avatar: avatar,
            notes: meta("og:description", in: html) ?? "",
            // A list without films shows Letterboxd's own picture.
            banner: banner?.absoluteString.contains("/static/img/") == true ? nil : banner,
            count: count,
            likes: html.firstMatch(of: /data-like-count="(\d+)"/).flatMap { Int($0.1) },
            isRanked: html.contains("numbered-list-item"),
            films: posters(in: html),
            url: url
        )
    }

    // MARK: - Page parts

    /// The films a page shows as posters, in order, up to `limit`.
    static func posters(in html: String, limit: Int = 5) -> [LetterboxdPoster] {
        var seen = Set<String>()
        var films: [LetterboxdPoster] = []
        for tag in html.matches(of: /<div class="react-component" data-component-class="LazyPoster"[^>]*>/) {
            guard let slug = tag.0.firstMatch(of: /data-item-slug="([^"]+)"/).map({ String($0.1) }), isSlug(slug),
                  let name = tag.0.firstMatch(of: /data-item-name="([^"]+)"/).map({ HTMLText.decode(String($0.1)) }),
                  seen.insert(slug).inserted else { continue }
            films.append(LetterboxdPoster(slug: slug, name: name))
            if films.count == limit { break }
        }
        return films
    }

    /// The film a review is about, from the heading above it.
    private static func filmMasthead(in html: String) -> (title: String, slug: String, year: String?)? {
        guard let heading = html.firstMatch(of: /<h2 class="primaryname[^"]*"><a href="\/film\/([a-z0-9-]+)\/">([^<]+)<\/a><\/h2>(?:<span class="releasedate"><a[^>]*>(\d{4})<\/a>)?/) else { return nil }
        return (HTMLText.decode(String(heading.2)), String(heading.1), heading.3.map(String.init))
    }

    /// The member at the top of a review or list: their display name and avatar.
    private static func owner(in html: String) -> (name: String?, avatar: URL?) {
        guard let summary = section(of: html, from: #"<div class="person-summary"#, to: "</h1>") else { return (nil, nil) }
        let name = summary.firstMatch(of: /class="name">\s*<span>([^<]+)<\/span>/).map { HTMLText.decode(String($0.1)) }
        let avatar = summary.firstMatch(of: /<img src="([^"]+)"/).flatMap { URL(string: HTMLText.decode(String($0.1))) }.flatMap(webImage)
        return (name, avatar)
    }

    /// `<meta property="og:…" content="…">`, or `name="…"` when `named`.
    static func meta(_ key: String, named: Bool = false, in html: String) -> String? {
        let attribute = named || key.hasPrefix("twitter:") ? "name" : "property"
        guard let start = html.range(of: #"<meta \#(attribute)="\#(key)" content=""#) else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return HTMLText.decode(String(rest[..<end]))
    }

    /// The text from the first `start` to the `end` after it.
    private static func section(of html: String, from start: String, to end: String) -> Substring? {
        guard let from = html.range(of: start), let to = html.range(of: end, range: from.upperBound..<html.endIndex) else { return nil }
        return html[from.lowerBound..<to.upperBound]
    }

    /// Images only from the web, not this Mac or its network.
    private static func webImage(_ url: URL) -> URL? {
        url.scheme == "https" && !LocalNetwork.contains(url) ? url : nil
    }
}

/// Text from bits of HTML.
enum HTMLText {
    /// Paragraphs and line breaks become new lines; other tags go.
    static func plain(_ html: String) -> String {
        var text = html.replacing(/<\/p>\s*<p[^>]*>/, with: "\n\n")
        text = text.replacing(/<br\s*\/?>/, with: "\n")
        text = text.replacing(/<[^>]+>/, with: "")
        let lines = decode(text).split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
        return lines.joined(separator: "\n").replacing(/\n{3,}/, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Character references: named ones pages use, and numbered ones.
    static func decode(_ string: String) -> String {
        guard string.contains("&") else { return string }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "lrm": "", "rlm": "",
                     "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•"]
        return string.replacing(/&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);/) { match in
            let name = String(match.1)
            if let character = named[name] { return character }
            guard name.hasPrefix("#") else { return String(match.0) }
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.0)
        }
    }
}

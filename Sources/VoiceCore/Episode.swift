import Foundation

/// Eine Folge einer Show.
/// - Joyn: `id` ist der Slug aus der Joyn-Adresse, z. B. "16-1-blind-auditions-1-pures-gaensehaut-feeling-zum-auftakt",
///   `show` der Serien-Slug (z. B. "the-voice-of-germany").
/// - Eigene Show: `id` ist die ID des Links, `url` die eigene Adresse.
public struct Episode: Codable, Identifiable, Hashable, Sendable {
    /// Die ursprüngliche Show – Standard für alte Daten und Anfragen ohne Show.
    public static let series = "the-voice-of-germany"

    public let id: String
    /// Staffel (0 = eigene Show ohne Staffeln)
    public let season: Int
    public let number: Int
    /// z. B. "Blind Auditions 1"
    public let title: String
    /// z. B. "Pures gaensehaut feeling zum auftakt"
    public let subtitle: String
    /// ID der Show, zu der die Folge gehört
    public var show: String
    /// Eigene Adresse (eigene Shows, YouTube)
    public var url: String?
    /// Vorschaubild (YouTube)
    public var thumbnail: String?
    /// Gruppe innerhalb der Show, bei YouTube "Videos" oder "Shorts" (`Episode.shorts`)
    public var group: String?

    public static let videos = "Videos"
    public static let shorts = "Shorts"
    /// Hochformat-Vorschaubild (Shorts)
    public var isShort: Bool { group == Episode.shorts }

    public init?(slug: String, series: String = Episode.series) {
        let parts = slug.split(separator: "-").map(String.init)
        guard parts.count >= 2, let season = Int(parts[0]), let number = Int(parts[1]) else { return nil }
        let names = Episode.makeTitle(Array(parts.dropFirst(2)), number: number)
        self.id = slug
        self.season = season
        self.number = number
        self.title = names.title
        self.subtitle = names.subtitle
        self.show = series
        self.url = nil
        self.thumbnail = nil
        self.group = nil
    }

    /// Folge mit allen Angaben (Netflix, Prime Video)
    public init(id: String, season: Int, number: Int, title: String, subtitle: String, show: String,
                url: String?, thumbnail: String?, group: String? = nil) {
        self.id = id
        self.season = season
        self.number = number
        self.title = title
        self.subtitle = subtitle
        self.show = show
        self.url = url
        self.thumbnail = thumbnail
        self.group = group
    }

    /// Folge aus einem eigenen Link
    public init(link: ShowLink, number: Int, show: String, subtitle: String? = nil) {
        self.id = link.id
        self.season = 0
        self.number = number
        self.title = link.title.isEmpty ? "Link \(number)" : link.title
        self.subtitle = subtitle ?? URL(string: link.url)?.host ?? link.url
        self.show = show
        self.url = link.url
        self.thumbnail = link.image
        self.group = nil
    }

    /// YouTube-Video oder -Short. Kleinere `number` = neuer.
    /// Shorts werden im normalen Player geöffnet, damit dieselben Tasten (K, J, L, F) funktionieren.
    public init(youtubeVideo id: String, title: String, published: Date?, number: Int, show: String,
                isShort: Bool = false) {
        self.id = id
        self.season = 0
        self.number = number
        self.title = title
        if let published {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = "d. MMMM yyyy"
            self.subtitle = formatter.string(from: published)
        } else {
            self.subtitle = ""
        }
        self.show = show
        self.url = "https://www.youtube.com/watch?v=\(id)"
        // Shorts: hqdefault gibt es immer (Hochformat-Bild "oardefault" fehlt manchmal); der Short steht darin
        // mittig zwischen schwarzen Rändern und wird beim Anzeigen auf 9:16 zugeschnitten.
        self.thumbnail = "https://i.ytimg.com/vi/\(id)/\(isShort ? "hqdefault" : "mqdefault").jpg"
        self.group = isShort ? Episode.shorts : Episode.videos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        season = try container.decode(Int.self, forKey: .season)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        // Ältere Daten kennen nur The Voice
        show = try container.decodeIfPresent(String.self, forKey: .show) ?? Episode.series
        url = try container.decodeIfPresent(String.self, forKey: .url)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        group = try container.decodeIfPresent(String.self, forKey: .group)
    }

    /// Eindeutig über alle Shows hinweg (für Listen mit Folgen mehrerer Shows)
    public var key: String { "\(show)/\(id)" }

    /// Seite der Folge auf joyn.de
    public var pageURL: URL { URL(string: "https://www.joyn.de/serien/\(show)/\(id)")! }
    /// Startet direkt den Player (bzw. öffnet den eigenen Link)
    public var playURL: URL? {
        if let url { return URL(string: url) }
        return URL(string: "https://www.joyn.de/play/serien/\(show)/\(id)")
    }
    /// z. B. "S16 F03" bzw. "Nr. 3" bei eigenen Shows
    public var code: String {
        season > 0 ? String(format: "S%d F%02d", season, number) : "Nr. \(number)"
    }

    /// Sortierung für die Anzeige: neueste Staffel zuerst, Folgen aufsteigend.
    public static func displayOrder(_ a: Episode, _ b: Episode) -> Bool {
        a.season != b.season ? a.season > b.season : a.number < b.number
    }

    static func makeTitle(_ words: [String], number: Int) -> (title: String, subtitle: String) {
        guard !words.isEmpty else { return ("Folge \(number)", "") }
        // "blind auditions 1 pures ..." -> Titel bis zur ersten Zahl, Rest als Untertitel
        if let index = words.firstIndex(where: { Int($0) != nil }) {
            let head = words[...index].map(capitalizeFirst).joined(separator: " ")
            let tail = words[(index + 1)...].joined(separator: " ")
            return (head, capitalizeFirst(tail))
        }
        // Kein Formatname mit Nummer (z. B. "halbfinale", "himmlisch schoenes shooting"): ganzer Text als Titel
        return (capitalizeFirst(words.joined(separator: " ")), "")
    }

    static func capitalizeFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

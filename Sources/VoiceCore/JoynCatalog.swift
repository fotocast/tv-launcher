import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Liest die Folgen einer Serie von joyn.de (eine Instanz pro Serie).
///
/// - Die Serienseite liefert die aktuelle Staffel.
/// - Jede Folgenseite listet alle Folgen ihrer Staffel.
/// - Für die vorherige Staffel wird einmalig eine Folge in der Joyn-Sitemap gesucht.
///   Danach ist sie im Cache und wird nicht mehr gesucht.
public actor JoynCatalog {
    public enum CatalogError: LocalizedError {
        case noEpisodesFound
        case http(Int, URL)

        public var errorDescription: String? {
            switch self {
            case .noEpisodesFound:
                return "Auf joyn.de wurden keine Folgen gefunden."
            case .http(let code, let url):
                return "joyn.de antwortet mit Status \(code) (\(url.lastPathComponent))."
            }
        }
    }

    static let base = "https://www.joyn.de"
    /// Notfall-Einstieg, falls die Sitemap nicht erreichbar ist.
    static let fallbackSeeds: [String: [Int: String]] = [
        Episode.series: [15: "15-1-blind-auditions-1-neue-talente-neue-traeume"],
    ]
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Serien-Slug, z. B. "the-voice-of-germany"
    public let series: String
    private let cacheFile: URL
    private let session: URLSession
    private let logger: @Sendable (String) -> Void
    /// Alle jemals gefundenen Folgen (Schlüssel: Slug)
    private var known: [String: Episode]

    public init(series: String = Episode.series, cacheFile: URL,
                logger: @escaping @Sendable (String) -> Void = { print($0) }) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": JoynCatalog.userAgent,
            "Accept-Language": "de-DE,de;q=0.9",
        ]
        var loaded: [String: Episode] = [:]
        if let data = try? Data(contentsOf: cacheFile),
           let list = try? JSONCoding.decoder.decode([Episode].self, from: data) {
            for var episode in list {
                episode.show = series
                loaded[episode.id] = episode
            }
        }
        self.series = series
        self.cacheFile = cacheFile
        self.logger = logger
        self.session = URLSession(configuration: configuration)
        self.known = loaded
    }

    /// Lädt neu von joyn.de und gibt aktuelle + vorherige Staffel zurück.
    public func refresh() async throws -> [Episode] {
        // 1. Serienseite -> aktuelle Staffel
        let seriesHTML = try await fetch("\(Self.base)/serien/\(series)")
        var found = Self.episodes(in: seriesHTML, series: series)
        guard let current = found.map(\.season).max() else { throw CatalogError.noEpisodesFound }

        // 2. Eine Folgenseite der aktuellen Staffel listet die komplette Staffel
        if let seed = found.filter({ $0.season == current }).min(by: { $0.number < $1.number }),
           let html = try? await fetch(seed.pageURL.absoluteString) {
            found += Self.episodes(in: html, series: series)
        }
        merge(found)

        // 3. Vorherige Staffel (nur suchen, wenn noch nicht bekannt)
        let previous = current - 1
        if previous > 0, !known.values.contains(where: { $0.season == previous }),
           let seed = await findSeed(season: previous) {
            merge([seed])
            if let html = try? await fetch(seed.pageURL.absoluteString) {
                merge(Self.episodes(in: html, series: series))
            }
        }

        save()
        logger("\(series): Folgen geladen, Staffel \(current) und \(previous)")
        return selection(current: current)
    }

    /// Letzter bekannter Stand ohne Netzwerkzugriff.
    public func cachedSelection() -> [Episode] {
        guard let current = known.values.map(\.season).max() else { return [] }
        return selection(current: current)
    }

    // MARK: - Intern

    private func selection(current: Int) -> [Episode] {
        known.values
            .filter { $0.season == current || $0.season == current - 1 }
            .sorted(by: Episode.displayOrder)
    }

    private func findSeed(season: Int) async -> Episode? {
        logger("\(series): Suche Staffel \(season) in der Joyn-Sitemap …")
        let needle = "/serien/\(series)/\(season)-"
        if let index = try? await fetch("\(Self.base)/sitemap.xml") {
            let maps = Self.matches(of: "<loc>\\s*([^<\\s]*sitemap\\.episode[^<\\s]*)\\s*</loc>", in: index)
            for map in maps {
                guard let xml = try? await fetch(map), xml.contains(needle) else { continue }
                if let episode = Self.episodes(in: xml, series: series).first(where: { $0.season == season }) {
                    return episode
                }
            }
        }
        if let slug = Self.fallbackSeeds[series]?[season] { return Episode(slug: slug, series: series) }
        logger("\(series): Staffel \(season) nicht gefunden.")
        return nil
    }

    /// Fügt Folgen hinzu. Hat Joyn den Slug einer Folge geändert, ersetzt der neue den alten.
    private func merge(_ list: [Episode]) {
        for episode in list {
            for (key, old) in known where key != episode.id && old.season == episode.season && old.number == episode.number {
                known[key] = nil
            }
            known[episode.id] = episode
        }
    }

    private func save() {
        let list = known.values.sorted(by: Episode.displayOrder)
        do {
            try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONCoding.encoder.encode(list).write(to: cacheFile, options: .atomic)
        } catch {
            logger("Cache konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    private func fetch(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.http(http.statusCode, url)
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Parsing (statisch, damit es testbar ist)

    /// Findet alle Folgen-Links wie "/serien/the-voice-of-germany/16-1-…" (keine BTS-Artikel).
    public static func episodes(in html: String, series: String) -> [Episode] {
        let escaped = NSRegularExpression.escapedPattern(for: series)
        let pattern = "(?<!/bts)/serien/\(escaped)/(\\d+-\\d+[a-z0-9-]*)"
        return matches(of: pattern, in: html)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
            .compactMap { Episode(slug: $0, series: series) }
    }

    public static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }
    }
}

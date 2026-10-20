import Foundation

/// Liest öffentliche Titelseiten von Netflix und Prime Video (ohne Anmeldung).
/// - Netflix: `netflix.reactContext` der Titelseite enthält alle Staffeln und Folgen mit `videoId`;
///   abgespielt wird über https://www.netflix.com/watch/<videoId>.
/// - Prime Video: die Detailseite einer Staffel enthält deren Folgen (Titel, Beschreibung, Bild). Die Adresse
///   einzelner Folgen steht nur für angemeldete Nutzer in der Seite – daher öffnet jede Folge die Staffel mit Autoplay.
/// - Disney+ zeigt ohne Anmeldung keine Inhalte und wird nur als Link-Sammlung unterstützt.
public struct Streaming: Sendable {
    public struct Title: Sendable {
        public var name: String
        public var image: String?
        public var episodes: [Episode]
    }

    public struct StreamingError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.httpAdditionalHeaders = [
            "User-Agent": JoynCatalog.userAgent,
            "Accept-Language": "de-DE,de;q=0.9",
        ]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Netflix

    public func netflix(titleID: String, show: String) async throws -> Title {
        let html = try await fetch("https://www.netflix.com/de/title/\(titleID)")
        guard let start = html.range(of: "netflix.reactContext = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex) else {
            throw StreamingError(message: "Netflix-Titel \(titleID) nicht gefunden.")
        }
        let raw = Self.unescapeHex(String(html[start.upperBound..<end.lowerBound]))
        guard let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)),
              let video = Self.find(in: json, where: { dict in
                  ["Show", "Movie"].contains(dict["__typename"] as? String ?? "") && dict["videoId"] != nil
                      && dict["title"] is String
              }) else {
            throw StreamingError(message: "Netflix-Titel \(titleID) konnte nicht gelesen werden.")
        }
        let name = video["title"] as? String ?? "Netflix"
        let image = Self.firstURL(in: video, keys: ["billboardOrStoryArt960", "eclipseBillboardRedux1280", "boxart"])
        var episodes: [Episode] = []
        let seasons = ((video["seasons"] as? [String: Any])?["edges"] as? [[String: Any]]) ?? []
        for (index, edge) in seasons.enumerated() {
            guard let season = edge["node"] as? [String: Any] else { continue }
            let list = ((season["episodes"] as? [String: Any])?["edges"] as? [[String: Any]]) ?? []
            for item in list {
                guard let node = item["node"] as? [String: Any], let id = Self.idString(node["videoId"]) else { continue }
                let number = node["number"] as? Int ?? episodes.count + 1
                episodes.append(Episode(
                    id: id, season: index + 1, number: number,
                    title: node["title"] as? String ?? "Folge \(number)",
                    subtitle: node["shortSynopsis"] as? String ?? "",
                    show: show, url: "https://www.netflix.com/watch/\(id)",
                    thumbnail: Self.firstURL(in: node, keys: ["merchStill300"])))
            }
        }
        if episodes.isEmpty, let id = Self.idString(video["videoId"]) {
            // Film: eine einzige „Folge“
            episodes = [Episode(id: id, season: 0, number: 1, title: name, subtitle: "Netflix-Film", show: show,
                                url: "https://www.netflix.com/watch/\(id)", thumbnail: image)]
        }
        return Title(name: name, image: image ?? episodes.first?.thumbnail, episodes: episodes)
    }

    // MARK: - Prime Video

    public func prime(pageID: String, show: String) async throws -> Title {
        let pageURL = "https://www.primevideo.com/-/de/detail/\(pageID)"
        let html = try await fetch(pageURL)
        let pageTitle = JoynCatalog.matches(of: "<title>([^<]*)</title>", in: html).first.map(YouTube.decodeEntities) ?? ""
        var name = pageTitle.replacingOccurrences(of: "Prime Video: ", with: "")
        if let range = name.range(of: #" - Staffel \d+$"#, options: .regularExpression) { name.removeSubrange(range) }
        let season = JoynCatalog.matches(of: #"Staffel (\d+)"#, in: pageTitle).first.flatMap(Int.init)
            ?? JoynCatalog.matches(of: #""seasonNumber":(\d+)"#, in: html).first.flatMap(Int.init) ?? 1
        let image = JoynCatalog.matches(of: #"<meta property="og:image" content="([^"]*)""#, in: html).first
        // Alle Folgen der Staffel starten über die Staffelseite (Autoplay)
        let playURL = "https://www.primevideo.com/detail/\(pageID)?autoplay=1&t=0"
        var episodes: [Episode] = []
        // Das Feld kommt mehrfach vor (das erste ist oft leer) – alle lesen
        var searchStart = html.startIndex
        var entries: [String: Any] = [:]
        while let range = html.range(of: #""detail":{"detail":"#, range: searchStart..<html.endIndex) {
            searchStart = range.upperBound
            guard range.upperBound < html.endIndex,
                  let object = Self.jsonObject(in: html, from: range.upperBound),
                  let part = try? JSONSerialization.jsonObject(with: Data(object.utf8)) as? [String: Any] else { continue }
            entries.merge(part) { first, _ in first }
        }
        do {
            for (gti, value) in entries {
                guard let entry = value as? [String: Any], let number = entry["episodeNumber"] as? Int else { continue }
                let images = entry["images"] as? [String: Any]
                episodes.append(Episode(
                    id: "\(season)-\(number)-\(gti.suffix(8))", season: season, number: number,
                    title: entry["title"] as? String ?? "Folge \(number)",
                    subtitle: entry["synopsis"] as? String ?? "",
                    show: show, url: playURL,
                    thumbnail: images?["covershot"] as? String ?? images?["packshot"] as? String))
            }
        }
        episodes.sort { $0.number < $1.number }
        guard !name.isEmpty, name != "Seite wurde nicht gefunden" else {
            throw StreamingError(message: "Prime-Video-Titel \(pageID) nicht gefunden.")
        }
        if episodes.isEmpty {
            // Film: eine einzige „Folge“
            episodes = [Episode(id: pageID, season: 0, number: 1, title: name, subtitle: "Prime Video", show: show,
                                url: playURL, thumbnail: image)]
        }
        return Title(name: name, image: image, episodes: episodes)
    }

    // MARK: - Einzelne Links

    /// Titel und Bild einer beliebigen Seite (og:title, <title>, og:image) – für Sammlungen
    public func pageInfo(_ url: String) async -> (title: String?, image: String?) {
        guard let html = try? await fetch(url) else { return (nil, nil) }
        let og = JoynCatalog.matches(of: #"<meta property="og:title" content="([^"]*)""#, in: html).first
        let title = og ?? JoynCatalog.matches(of: "<title>([^<]*)</title>", in: html).first
        let image = JoynCatalog.matches(of: #"<meta property="og:image" content="([^"]*)""#, in: html).first
        return (title.map(YouTube.decodeEntities), image.map(YouTube.decodeEntities))
    }

    // MARK: - Hilfen

    private func fetch(_ url: String) async throws -> String {
        guard let address = URL(string: url) else { throw StreamingError(message: "Ungültige Adresse") }
        let (data, response) = try await session.data(from: address)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StreamingError(message: "\(address.host ?? "Seite") antwortet mit Status \(http.statusCode).")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Netflix schreibt Sonderzeichen als \xNN
    static func unescapeHex(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\\x([0-9a-fA-F]{2})"#) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let hex = ns.substring(with: match.range(at: 1))
            let scalar = UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init) ?? " "
            // Anführungszeichen und Backslash müssen im JSON maskiert bleiben
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            default: result += String(Character(scalar))
            }
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// Ein JSON-Objekt ab `start` (das „{“) bis zur passenden schließenden Klammer
    static func jsonObject(in text: String, from start: String.Index) -> String? {
        guard text[start] == "{" else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == "\"" { inString = false }
            } else if char == "\"" {
                inString = true
            } else if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func find(in value: Any, where match: ([String: Any]) -> Bool) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if match(dict) { return dict }
            for child in dict.values { if let found = find(in: child, where: match) { return found } }
        } else if let array = value as? [Any] {
            for child in array { if let found = find(in: child, where: match) { return found } }
        }
        return nil
    }

    private static func firstURL(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys { if let url = (dict[key] as? [String: Any])?["url"] as? String { return url } }
        return nil
    }

    private static func idString(_ value: Any?) -> String? {
        if let int = value as? Int { return String(int) }
        if let number = value as? NSNumber { return number.stringValue }
        return value as? String
    }
}

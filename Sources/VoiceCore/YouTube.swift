import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Liest YouTube-Kanäle ohne API-Schlüssel.
///
/// - Kanal ermitteln: Kanalseite (oder Videoseite) laden und die Kanal-ID "UC…" sowie Name und Bild auslesen.
/// - Videos: RSS-Feed des Kanals (stabil, die 15 neuesten mit Datum) plus – falls möglich – die Videoseite
///   des Kanals (etwa 30 Videos). Fällt die Videoseite aus, reicht der Feed.
public struct YouTube: Sendable {
    public struct Channel: Sendable {
        public let id: String
        public let name: String
        public let image: String?
    }

    public enum YouTubeError: LocalizedError {
        case channelNotFound(String)
        case noVideos

        public var errorDescription: String? {
            switch self {
            case .channelNotFound(let input):
                return "Kein YouTube-Kanal gefunden für „\(input)“. Bitte die Adresse der Kanalseite angeben (z. B. https://www.youtube.com/@name)."
            case .noVideos:
                return "Auf dem YouTube-Kanal wurden keine öffentlichen Videos gefunden."
            }
        }
    }

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": JoynCatalog.userAgent,
            "Accept-Language": "de-DE,de;q=0.9",
            // Überspringt die Cookie-Abfrage, die YouTube in der EU sonst vorschaltet
            "Cookie": "SOCS=CAI",
        ]
        session = URLSession(configuration: configuration)
    }

    static let channelIDPattern = "^UC[A-Za-z0-9_-]{22}$"

    // MARK: - Kanal ermitteln

    /// `input`: Kanal-ID, "@name", Kanal-Adresse oder Adresse eines Videos des Kanals.
    public func resolveChannel(_ input: String) async throws -> Channel {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageURL: URL?
        if text.range(of: Self.channelIDPattern, options: .regularExpression) != nil {
            pageURL = URL(string: "https://www.youtube.com/channel/\(text)")
        } else if text.hasPrefix("@") {
            pageURL = URL(string: "https://www.youtube.com/\(text)")
        } else if let url = URL(string: text.contains("://") ? text : "https://\(text)"),
                  url.host?.lowercased().hasSuffix("youtube.com") == true || url.host?.lowercased() == "youtu.be" {
            pageURL = url
        } else {
            pageURL = nil
        }
        guard let pageURL, let html = try? await fetch(pageURL) else { throw YouTubeError.channelNotFound(text) }

        // Kanalseite: canonical zeigt auf /channel/UC…; Videoseite: channelId in den Videodaten
        let id = Self.first(#"<link rel="canonical" href="https://www\.youtube\.com/channel/(UC[A-Za-z0-9_-]{22})""#, in: html)
            ?? Self.first(#""externalId":"(UC[A-Za-z0-9_-]{22})""#, in: html)
            ?? Self.first(#""channelId":"(UC[A-Za-z0-9_-]{22})""#, in: html)
        guard let id else { throw YouTubeError.channelNotFound(text) }

        // Name und Bild von der Kanalseite (bei einer Videoseite die Kanalseite nachladen)
        var channelHTML = html
        if !html.contains("/channel/\(id)\"") || Self.first(#""externalId":"(UC[^"]+)""#, in: html) == nil,
           let url = URL(string: "https://www.youtube.com/channel/\(id)"),
           let page = try? await fetch(url) {
            channelHTML = page
        }
        let name = Self.first(#"<meta property="og:title" content="([^"]*)""#, in: channelHTML).map(Self.decodeEntities)
        let image = Self.first(#"<meta property="og:image" content="([^"]*)""#, in: channelHTML).map(Self.decodeEntities)
        return Channel(id: id, name: name ?? "YouTube-Kanal", image: image)
    }

    // MARK: - Videos

    /// Neueste Videos und Shorts eines Kanals, jeweils neuestes zuerst.
    /// Videos bekommen die Nummern 1…n, Shorts danach n+1…, damit beide Gruppen getrennt sortiert bleiben.
    public func videos(channelID: String, show: String) async throws -> [Episode] {
        async let feed = try? feedVideos(channelID: channelID)
        async let videosTab = try? tabVideos(channelID: channelID, tab: "videos")
        async let shortsTab = try? tabVideos(channelID: channelID, tab: "shorts")
        let fromFeed = await feed ?? []
        let fromVideos = await videosTab ?? []
        let fromShorts = await shortsTab ?? []

        // Feed zuerst (hat das Datum), dann die Einträge der Kanal-Reiter
        var seen = Set<String>()
        func merge(_ feedPart: [FeedVideo], _ tab: [(id: String, title: String)]) -> [FeedVideo] {
            var list: [FeedVideo] = []
            for video in feedPart where seen.insert(video.id).inserted { list.append(video) }
            for video in tab where seen.insert(video.id).inserted {
                list.append(FeedVideo(id: video.id, title: video.title, published: nil, isShort: false))
            }
            return list
        }
        let videos = merge(fromFeed.filter { !$0.isShort }, fromVideos)
        let shorts = merge(fromFeed.filter(\.isShort), fromShorts)
        guard !videos.isEmpty || !shorts.isEmpty else { throw YouTubeError.noVideos }

        let videoEpisodes = videos.enumerated().map { index, video in
            Episode(youtubeVideo: video.id, title: video.title, published: video.published,
                    number: index + 1, show: show)
        }
        let shortEpisodes = shorts.enumerated().map { index, video in
            Episode(youtubeVideo: video.id, title: video.title, published: video.published,
                    number: videos.count + index + 1, show: show, isShort: true)
        }
        return videoEpisodes + shortEpisodes
    }

    private struct FeedVideo {
        let id: String
        let title: String
        let published: Date?
        let isShort: Bool
    }

    private func feedVideos(channelID: String) async throws -> [FeedVideo] {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)") else { return [] }
        let (data, _) = try await session.data(from: url)
        let parser = FeedParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        let iso = ISO8601DateFormatter()
        return parser.entries.compactMap { entry in
            guard let id = entry["yt:videoId"], let title = entry["title"] ?? entry["media:title"] else { return nil }
            // Shorts verlinken im Feed auf /shorts/<id> statt /watch?v=<id>
            let isShort = entry["link"]?.contains("/shorts/") ?? false
            return FeedVideo(id: id, title: title, published: entry["published"].flatMap(iso.date(from:)),
                             isShort: isShort)
        }
    }

    /// Videos bzw. Shorts aus den eingebetteten Daten eines Kanal-Reiters (ytInitialData).
    /// `tab`: "videos" oder "shorts"
    private func tabVideos(channelID: String, tab: String) async throws -> [(id: String, title: String)] {
        guard let url = URL(string: "https://www.youtube.com/channel/\(channelID)/\(tab)") else { return [] }
        let html = try await fetch(url)
        guard let start = html.range(of: "var ytInitialData = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8))
        else { return [] }

        var result: [(id: String, title: String)] = []
        func text(_ value: Any?, _ keys: String...) -> String? {
            var current = value
            for key in keys { current = (current as? [String: Any])?[key] }
            return current as? String
        }
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let lockup = dict["lockupViewModel"] as? [String: Any],
                   let id = lockup["contentId"] as? String,
                   (lockup["contentType"] as? String).map({ $0.contains("VIDEO") }) ?? true,
                   let title = text(lockup, "metadata", "lockupMetadataViewModel", "title", "content") {
                    result.append((id, title))
                } else if let short = dict["shortsLockupViewModel"] as? [String: Any],
                          let id = text(short, "onTap", "innertubeCommand", "reelWatchEndpoint", "videoId"),
                          let title = text(short, "overlayMetadata", "primaryText", "content") {
                    result.append((id, title))
                } else if let renderer = dict["videoRenderer"] as? [String: Any],
                          let id = renderer["videoId"] as? String,
                          let title = ((renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
                              .first?["text"] as? String {
                    result.append((id, title))
                }
                dict.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(json)
        return result
    }

    // MARK: - Hilfen

    private func fetch(_ url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func first(_ pattern: String, in text: String) -> String? {
        JoynCatalog.matches(of: pattern, in: text).first
    }

    public static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

/// Liest die Einträge eines YouTube-RSS-Feeds (Atom).
private final class FeedParser: NSObject, XMLParserDelegate {
    var entries: [[String: String]] = []
    private var current: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "entry" { current = [:] }
        if elementName == "link", current != nil, current?["link"] == nil, let href = attributes["href"] {
            current?["link"] = href
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        if elementName == "entry" {
            if let current { entries.append(current) }
            current = nil
        } else if current != nil, ["yt:videoId", "title", "media:title", "published"].contains(elementName),
                  current?[elementName] == nil {
            current?[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

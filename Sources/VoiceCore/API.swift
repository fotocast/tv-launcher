import Foundation

// Datentypen der HTTP-Schnittstelle des Servers (genutzt von Mac-App und Web-App):
//
//   GET  /api/health              -> {"ok": true}
//   GET  /api/shows               -> ShowsResponse  (alle Shows + zuletzt gespielte Folge)
//   POST /api/shows               <- {"show": Show}  -> ShowsResponse  (anlegen oder ändern)
//   POST /api/shows/delete        <- {"id": "<Show-ID>"}  -> ShowsResponse
//   POST /api/shows/order         <- {"ids": ["<Show-ID>", …]}  -> ShowsResponse  (eigene Reihenfolge)
//   GET  /api/episodes?show=<id>  -> CatalogResponse  (lädt bei Bedarf neu von joyn.de)
//   POST /api/refresh?show=<id>   -> CatalogResponse  (erzwingt Neuladen)
//   POST /api/play                <- {"show": "<id>", "id": "<Folge>"}  -> PlayResponse
//   POST /api/control             <- {"action": "playpause" | "back" | "forward" | "fullscreen"}  -> PlayResponse
//                                    (Tasten der Show, die zuletzt gestartet wurde)
//   POST /api/movies             <- {"movie": "<Joyn-Film-Adresse oder Slug>", "play": true|false}  -> PlayResponse
//                                    (merkt den Film in der Sammlung "Filme", startet ihn auf Wunsch sofort)
//   GET  /api/screenshot          -> image/jpeg  (Bildschirm des Mac mini, längste Seite höchstens 1600 px)
//   POST /api/youtube             <- {"video": "<YouTube-Link oder Video-ID>", "play": true|false}  -> PlayResponse
//                                    (merkt das Video in der Sammlung "YouTube-Videos", startet es auf Wunsch sofort)
//   POST /api/input               <- {"events": [InputEvent]}  -> PlayResponse  (Fernsteuer-Modus)
// Fehlt "show", gilt The Voice of Germany.

public struct CatalogResponse: Codable, Sendable {
    public var episodes: [Episode]
    public var lastPlayedID: String?
    public var updatedAt: Date?

    public init(episodes: [Episode], lastPlayedID: String?, updatedAt: Date?) {
        self.episodes = episodes
        self.lastPlayedID = lastPlayedID
        self.updatedAt = updatedAt
    }
}

public struct PlayRequest: Codable, Sendable {
    public var show: String?
    public var id: String
    public init(show: String?, id: String) {
        self.show = show
        self.id = id
    }
}

/// Verweis auf eine Folge einer Show
public struct EpisodeRef: Codable, Hashable, Sendable {
    public var show: String
    public var id: String
    public init(show: String, id: String) {
        self.show = show
        self.id = id
    }
}

public struct ShowsResponse: Codable, Sendable {
    /// Shows in der eigenen Reihenfolge
    public var shows: [Show]
    /// Zuletzt gestartete Folge (über alle Shows)
    public var lastPlayed: EpisodeRef?
    /// Wann zuletzt eine Folge der Show gestartet wurde (Show-ID → Zeitpunkt)
    public var playedAt: [String: Date]?
    public init(shows: [Show], lastPlayed: EpisodeRef?, playedAt: [String: Date]? = nil) {
        self.shows = shows
        self.lastPlayed = lastPlayed
        self.playedAt = playedAt
    }
}

/// Neue Reihenfolge der Shows (alle Show-IDs in gewünschter Reihenfolge)
public struct ShowOrderRequest: Codable, Sendable {
    public var ids: [String]
    public init(ids: [String]) { self.ids = ids }
}

public struct MovieRequest: Codable, Sendable {
    public var movie: String
    public var play: Bool
    public init(movie: String, play: Bool) {
        self.movie = movie
        self.play = play
    }
}

public struct YouTubeVideoRequest: Codable, Sendable {
    public var video: String
    public var play: Bool
    public init(video: String, play: Bool) {
        self.video = video
        self.play = play
    }
}

public struct ShowRequest: Codable, Sendable {
    public var show: Show
    public init(show: Show) { self.show = show }
}

public struct DeleteShowRequest: Codable, Sendable {
    public var id: String
    public init(id: String) { self.id = id }
}

/// Steuerbefehle für den laufenden Player auf dem Mac mini.
/// Welche Taste dafür gedrückt wird, legt die Show fest (`ShowControls`).
public enum PlayerAction: String, Codable, CaseIterable, Sendable {
    /// Pause/Weiter (Joyn: Leertaste)
    case playPause = "playpause"
    /// Zurückspulen (Joyn: Pfeil links, 10 Sekunden)
    case back
    /// Vorspulen (Joyn: Pfeil rechts, 10 Sekunden)
    case forward
    /// Vollbild an/aus (Joyn: Doppelklick auf die Bildmitte)
    case fullscreen

    public var label: String {
        switch self {
        case .playPause: return "Pause/Weiter"
        case .back: return "Zurückspulen"
        case .forward: return "Vorspulen"
        case .fullscreen: return "Vollbild"
        }
    }
}

public struct ControlRequest: Codable, Sendable {
    public var action: PlayerAction
    public init(action: PlayerAction) { self.action = action }
}

/// Eine Tastatur- oder Mauseingabe, die im Fernsteuer-Modus vom MacBook
/// an den Mac mini übertragen und dort abgespielt wird.
public struct InputEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Taste (`code` = macOS-Tastencode, `down`, `flags` = Modifier wie ⌘⇧)
        case key
        /// Zeiger relativ bewegen (`dx`, `dy` in Pixeln)
        case move
        /// Zeiger an eine Stelle setzen (`dx`, `dy` = 0…1 relativ zum Hauptbildschirm, z. B. aus einem Bildschirmfoto)
        case moveTo
        /// Maustaste (`button` 0 = links, 1 = rechts, 2 = andere; `down`, `clicks`)
        case button
        /// Scrollen (`dx`, `dy` in Pixeln)
        case scroll
        /// Alle gedrückten Tasten und Maustasten loslassen (beim Beenden des Modus)
        case reset
    }

    public var kind: Kind
    public var code: UInt16?
    public var down: Bool?
    public var flags: UInt64?
    public var button: Int?
    public var clicks: Int?
    public var dx: Double?
    public var dy: Double?

    public init(kind: Kind, code: UInt16? = nil, down: Bool? = nil, flags: UInt64? = nil,
                button: Int? = nil, clicks: Int? = nil, dx: Double? = nil, dy: Double? = nil) {
        self.kind = kind
        self.code = code
        self.down = down
        self.flags = flags
        self.button = button
        self.clicks = clicks
        self.dx = dx
        self.dy = dy
    }
}

public struct InputBatch: Codable, Sendable {
    public var events: [InputEvent]
    public init(events: [InputEvent]) { self.events = events }
}

public struct PlayResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}

public struct APIError: Codable, Sendable {
    public var error: String
    public init(error: String) { self.error = error }
}

public enum JSONCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Bonjour: der Server meldet sich im lokalen Netz, damit die Mac-App ihn ohne Adresse findet.
/// TXT-Eintrag: `host` (z. B. "Mac-mini.local") und `port`.
public enum Discovery {
    public static let serviceType = "_tvlauncher._tcp"
}

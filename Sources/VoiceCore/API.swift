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

/// Show anlegen nur aus einer Eingabe (für die Web-App): Der Server baut die Show mit Standard-Tasten.
/// `kind`: "joyn" (`input` = Serien-Adresse oder Slug), "youtube" (Kanal-/Video-Adresse oder @Name),
/// "custom" (nur `name`). Ohne `name` ermittelt der Server einen.
public struct AddShowRequest: Codable, Sendable {
    public var kind: Show.Kind
    public var input: String?
    public var name: String?
    /// Ordner für die neue Show (optional)
    public var folder: String?
    public init(kind: Show.Kind, input: String?, name: String?, folder: String? = nil) {
        self.kind = kind
        self.input = input
        self.name = name
        self.folder = folder
    }
}

/// Gespeicherte Tastenbelegung, die sich auf jede Show anwenden lässt.
/// Eingebaute Vorlagen (`builtIn`) liefert der Server mit, sie lassen sich nicht ändern oder löschen.
public struct KeyPreset: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var controls: ShowControls
    public var builtIn: Bool?

    public init(id: String, name: String, controls: ShowControls, builtIn: Bool? = nil) {
        self.id = id
        self.name = name
        self.controls = controls
        self.builtIn = builtIn
    }

    public var isBuiltIn: Bool { builtIn ?? false }

    public static let builtIns = [
        KeyPreset(id: "builtin-joyn", name: "Joyn", controls: .joynDefault, builtIn: true),
        KeyPreset(id: "builtin-youtube", name: "YouTube", controls: .youtubeDefault, builtIn: true),
        KeyPreset(id: "builtin-custom", name: "Standard (Leertaste, Pfeile, F)", controls: .customDefault, builtIn: true),
    ]

    /// Kurzbeschreibung, z. B. "K · J/L · F · C · Start K nach 5 s"
    public var summary: String {
        let c = controls
        var parts = [c.playPause.label, "\(c.back.label)/\(c.forward.label)", c.fullscreen.label]
        if c.subtitles.kind != .none { parts.append("Untertitel \(c.subtitles.label)") }
        if c.start.kind != .none { parts.append("Start \(c.start.label) nach \(Int(c.startDelay)) s") }
        return parts.joined(separator: " · ")
    }
}

public struct PresetsResponse: Codable, Sendable {
    public var presets: [KeyPreset]
    public init(presets: [KeyPreset]) { self.presets = presets }
}

/// Preset sichern: gleicher Name ersetzt ein vorhandenes eigenes Preset
public struct PresetRequest: Codable, Sendable {
    public var preset: KeyPreset
    public init(preset: KeyPreset) { self.preset = preset }
}

/// Ordner umbenennen (`to`) oder auflösen (`to` leer) – betrifft alle Shows mit `folder == from`
public struct FolderRenameRequest: Codable, Sendable {
    public var from: String
    public var to: String
    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
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
    /// Untertitel an/aus (YouTube: C; Joyn hat keine Taste dafür)
    case subtitles
    /// Aktuellen Browser-Tab schließen (immer ⌘W)
    case closeTab = "closetab"

    public var label: String {
        switch self {
        case .playPause: return "Pause/Weiter"
        case .back: return "Zurückspulen"
        case .forward: return "Vorspulen"
        case .fullscreen: return "Vollbild"
        case .subtitles: return "Untertitel"
        case .closeTab: return "Tab schließen"
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

/// Ergebnis von `GET /api/youtube/search?q=…` (Web-App: YouTube durchsuchen)
public struct YouTubeSearchResponse: Codable, Sendable {
    public struct Video: Codable, Sendable, Hashable {
        public var id: String
        public var title: String
        public var channel: String?
        public var channelID: String?
        /// z. B. "12:34" (fehlt bei Shorts und Livestreams)
        public var duration: String?
        /// z. B. "vor 3 Tagen"
        public var published: String?
        /// z. B. "1.032 Aufrufe"
        public var views: String?
        public var thumbnail: String
        public var isShort: Bool
        public init(id: String, title: String, channel: String?, channelID: String?, duration: String?,
                    published: String?, views: String?, thumbnail: String, isShort: Bool) {
            self.id = id
            self.title = title
            self.channel = channel
            self.channelID = channelID
            self.duration = duration
            self.published = published
            self.views = views
            self.thumbnail = thumbnail
            self.isShort = isShort
        }
    }

    public struct Channel: Codable, Sendable, Hashable {
        public var id: String
        public var name: String
        /// z. B. "@tagesschau"
        public var handle: String?
        public var subscribers: String?
        public var image: String?
        /// Schon als Show hinzugefügt
        public var added: Bool
        public init(id: String, name: String, handle: String?, subscribers: String?, image: String?, added: Bool) {
            self.id = id
            self.name = name
            self.handle = handle
            self.subscribers = subscribers
            self.image = image
            self.added = added
        }
    }

    public var query: String
    public var videos: [Video]
    public var channels: [Channel]
    public init(query: String, videos: [Video], channels: [Channel]) {
        self.query = query
        self.videos = videos
        self.channels = channels
    }
}

/// Bonjour: der Server meldet sich im lokalen Netz, damit die Mac-App ihn ohne Adresse findet.
/// TXT-Eintrag: `host` (z. B. "Mac-mini.local") und `port`.
public enum Discovery {
    public static let serviceType = "_tvlauncher._tcp"
}

// MARK: - Einstellungen des Servers (Mac am Fernseher)

/// Versionsnummer von App, Web-App und Server
public enum TVLauncher {
    public static let version = "1.3"
}

/// Einstellungen, die auf dem Server gespeichert werden und für App und Web-App gelten.
public struct ServerSettings: Codable, Hashable, Sendable {
    /// Nach dem Start automatisch Vollbild (Taste/Doppelklick „Vollbild“ der Show)
    public var autoFullscreen: Bool
    /// Sekunden nach der Start-Taste bis zum Vollbild
    public var fullscreenDelay: Double
    /// Lautstärke beim Start eines Videos (0…100), `nil` = nicht verändern
    public var startVolume: Int?
    /// Wie viele Joyn-Staffeln geladen werden (0 = alle)
    public var joynSeasons: Int
    /// Wie oft YouTube-Kanäle neu geladen werden (Minuten)
    public var youtubeRefreshMinutes: Int

    public init(autoFullscreen: Bool = false, fullscreenDelay: Double = 3, startVolume: Int? = nil,
                joynSeasons: Int = 2, youtubeRefreshMinutes: Int = 30) {
        self.autoFullscreen = autoFullscreen
        self.fullscreenDelay = fullscreenDelay
        self.startVolume = startVolume
        self.joynSeasons = joynSeasons
        self.youtubeRefreshMinutes = youtubeRefreshMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ServerSettings()
        autoFullscreen = try c.decodeIfPresent(Bool.self, forKey: .autoFullscreen) ?? d.autoFullscreen
        fullscreenDelay = try c.decodeIfPresent(Double.self, forKey: .fullscreenDelay) ?? d.fullscreenDelay
        startVolume = try c.decodeIfPresent(Int.self, forKey: .startVolume)
        joynSeasons = try c.decodeIfPresent(Int.self, forKey: .joynSeasons) ?? d.joynSeasons
        youtubeRefreshMinutes = try c.decodeIfPresent(Int.self, forKey: .youtubeRefreshMinutes) ?? d.youtubeRefreshMinutes
    }

    /// Werte in sinnvolle Grenzen bringen
    public var clamped: ServerSettings {
        var s = self
        s.fullscreenDelay = min(max(s.fullscreenDelay, 0), 60)
        s.startVolume = s.startVolume.map { min(max($0, 0), 100) }
        s.joynSeasons = min(max(s.joynSeasons, 0), 50)
        s.youtubeRefreshMinutes = min(max(s.youtubeRefreshMinutes, 5), 24 * 60)
        return s
    }
}

public struct SettingsRequest: Codable, Sendable {
    public var settings: ServerSettings
    public init(settings: ServerSettings) { self.settings = settings }
}

/// Zustand des Servers für „Status & Wartung“
public struct ServerStatus: Codable, Sendable {
    public var version: String
    public var host: String
    public var browser: String
    public var closeOldTabs: Bool
    /// Berechtigung „Bedienungshilfen“ (Tasten, Klicks)
    public var accessibility: Bool
    /// Berechtigung „Bildschirmaufnahme“ (nur „Bildschirm anklicken“)
    public var screenRecording: Bool
    public var startedAt: Date
    /// Lautstärke am Mac (0…100) und stumm
    public var volume: Int?
    public var muted: Bool?
    /// Sleep-Timer läuft bis
    public var sleepAt: Date?

    public init(version: String, host: String, browser: String, closeOldTabs: Bool, accessibility: Bool,
                screenRecording: Bool, startedAt: Date, volume: Int?, muted: Bool?, sleepAt: Date?) {
        self.version = version
        self.host = host
        self.browser = browser
        self.closeOldTabs = closeOldTabs
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.startedAt = startedAt
        self.volume = volume
        self.muted = muted
        self.sleepAt = sleepAt
    }
}

/// Lautstärke: "up", "down", "mute" (umschalten) oder "set" mit `value`
public struct VolumeRequest: Codable, Sendable {
    public var action: String
    public var value: Int?
    public init(action: String, value: Int? = nil) {
        self.action = action
        self.value = value
    }
}

/// `volume`/`muted` fehlen, wenn der Mac die Lautstärke nicht regeln kann (Ton über HDMI) –
/// dann drückt der Server die Lautstärke-Tasten des Players und meldet das in `message`.
public struct VolumeResponse: Codable, Sendable {
    public var volume: Int?
    public var muted: Bool?
    public var message: String?
    public init(volume: Int?, muted: Bool?, message: String? = nil) {
        self.volume = volume
        self.muted = muted
        self.message = message
    }
}

/// Sleep-Timer: nach `minutes` pausieren und Display aus; 0 = abbrechen
public struct SleepRequest: Codable, Sendable {
    public var minutes: Int
    public init(minutes: Int) { self.minutes = minutes }
}

/// Sicherung aller Shows, Presets und Einstellungen (`GET /api/backup`, `POST /api/restore`)
public struct BackupFile: Codable, Sendable {
    public var app: String
    public var version: Int
    public var exportedAt: Date
    public var shows: [Show]
    public var presets: [KeyPreset]
    public var settings: ServerSettings

    public init(shows: [Show], presets: [KeyPreset], settings: ServerSettings, exportedAt: Date = Date()) {
        self.app = "TV Launcher"
        self.version = 1
        self.exportedAt = exportedAt
        self.shows = shows
        self.presets = presets
        self.settings = settings
    }
}

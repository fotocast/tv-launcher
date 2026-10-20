import Foundation
import VoiceCore

enum AppSettings {
    static let serverKey = "serverURL"
    /// Leer: die App sucht den Server per Bonjour (`ServerDiscovery`) und trägt ihn selbst ein
    static let defaultServer = ""
    static let pointerSpeedKey = "pointerSpeed"
    static let defaultPointerSpeed = 1.5
    /// „Bildschirm anklicken“: Sekunden zwischen zwei Bildschirmfotos ohne Klick (0 = nur nach Klicks)
    static let screenshotIntervalKey = "screenshotInterval"
    static let defaultScreenshotInterval = 60
    static let screenshotIntervals = [0, 5, 10, 15, 30, 60, 120, 300]

    static var screenshotInterval: Int {
        UserDefaults.standard.object(forKey: screenshotIntervalKey) as? Int ?? defaultScreenshotInterval
    }

    /// z. B. "alle 30 s", "jede Minute", "nur nach Klicks"
    static func intervalLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return String(localized: "nur nach Klicks")
        case 60: return String(localized: "jede Minute")
        case let s where s > 60 && s % 60 == 0: return String(localized: "alle \(s / 60) Minuten")
        default: return String(localized: "alle \(seconds) Sekunden")
        }
    }
    static let showSortKey = "showSort"
    /// IDs der eingeklappten Shows in der Seitenleiste, durch Zeilenumbrüche getrennt
    static let collapsedShowsKey = "collapsedShows"
    /// Sprache der App: "system", "de" oder "en" (wirkt nach Neustart)
    static let languageKey = "appLanguage"
    /// Fernsteuerung: Scrollrichtung umkehren
    static let invertScrollKey = "invertScroll"
    /// Tastenkürzel für Play/Pause usw. im Menü „Wiedergabe“
    static let playbackShortcutsKey = "playbackShortcuts"
    /// Startseite: ausgeblendete Abschnitte (durch Zeilenumbrüche getrennt) und Kachelgröße
    static let homeHiddenKey = "homeHiddenSections"
    static let tileSizeKey = "homeTileSize"

    /// Sprache, in der die App gerade läuft ("de" oder "en") – für Server-Meldungen
    static var languageCode: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "de"
    }
}

struct ClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Spricht mit dem TV-Launcher-Server auf dem Mac mini.
struct APIClient {
    var baseURL: URL

    /// Client für die Server-Adresse aus den Einstellungen, `nil` bei ungültiger Adresse.
    static func fromSettings() -> APIClient? {
        let raw = UserDefaults.standard.string(forKey: AppSettings.serverKey) ?? AppSettings.defaultServer
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil, url.host != nil else { return nil }
        return APIClient(baseURL: url)
    }

    func sendInput(_ events: [InputEvent]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/input"))
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encoder.encode(InputBatch(events: events))
        _ = try await send(request, as: PlayResponse.self)
    }

    /// Bildschirmfoto des Mac mini (JPEG)
    func screenshot() async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/screenshot"))
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONCoding.decoder.decode(APIError.self, from: data))?.error
            throw ClientError(message: message ?? "Bildschirmfoto nicht verfügbar")
        }
        return data
    }

    func shows() async throws -> ShowsResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/shows"))
        request.timeoutInterval = 15
        return try await send(request, as: ShowsResponse.self)
    }

    func saveShow(_ show: Show) async throws -> ShowsResponse {
        try await post("api/shows", ShowRequest(show: show), as: ShowsResponse.self, timeout: 15)
    }

    func reorderShows(_ ids: [String]) async throws -> ShowsResponse {
        try await post("api/shows/order", ShowOrderRequest(ids: ids), as: ShowsResponse.self, timeout: 15)
    }

    func presets() async throws -> PresetsResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/presets"))
        request.timeoutInterval = 15
        return try await send(request, as: PresetsResponse.self)
    }

    func savePreset(_ preset: KeyPreset) async throws -> PresetsResponse {
        try await post("api/presets", PresetRequest(preset: preset), as: PresetsResponse.self, timeout: 15)
    }

    func deletePreset(_ id: String) async throws -> PresetsResponse {
        try await post("api/presets/delete", DeleteShowRequest(id: id), as: PresetsResponse.self, timeout: 15)
    }

    func deleteShow(_ id: String) async throws -> ShowsResponse {
        try await post("api/shows/delete", DeleteShowRequest(id: id), as: ShowsResponse.self, timeout: 15)
    }

    func catalog(show: String, refresh: Bool) async throws -> CatalogResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent(refresh ? "api/refresh" : "api/episodes"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "show", value: show)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = refresh ? "POST" : "GET"
        // Die erste Suche nach der Vorjahresstaffel kann etwas dauern
        request.timeoutInterval = 150
        return try await send(request, as: CatalogResponse.self)
    }

    func play(_ episode: Episode) async throws -> PlayResponse {
        try await post("api/play", PlayRequest(show: episode.show, id: episode.id), as: PlayResponse.self, timeout: 20)
    }

    /// Merkt einen Joyn-Film (Adresse oder Slug) und startet ihn auf Wunsch sofort
    func movie(_ movie: String, play: Bool) async throws -> PlayResponse {
        try await post("api/movies", MovieRequest(movie: movie, play: play), as: PlayResponse.self, timeout: 30)
    }

    /// Einzelnes YouTube-Video merken und auf Wunsch sofort starten
    func youtube(_ video: String, play: Bool) async throws -> PlayResponse {
        try await post("api/youtube", YouTubeVideoRequest(video: video, play: play), as: PlayResponse.self, timeout: 30)
    }

    /// Verlauf der einzeln gestarteten YouTube-Videos löschen
    func clearYouTubeHistory() async throws -> ShowsResponse {
        try await post("api/youtube/clear", [String: String](), as: ShowsResponse.self, timeout: 15)
    }

    // MARK: Einstellungen, Status & Wartung

    func get<T: Decodable>(_ path: String, as type: T.Type, timeout: TimeInterval = 15) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = timeout
        return try await send(request, as: type)
    }

    func saveSettings(_ settings: ServerSettings) async throws -> ServerSettings {
        try await post("api/settings", SettingsRequest(settings: settings), as: ServerSettings.self, timeout: 15)
    }

    func volume(_ action: String, value: Int? = nil) async throws -> VolumeResponse {
        try await post("api/volume", VolumeRequest(action: action, value: value), as: VolumeResponse.self, timeout: 10)
    }

    func sleep(minutes: Int) async throws -> ServerStatus {
        try await post("api/sleep", SleepRequest(minutes: minutes), as: ServerStatus.self, timeout: 10)
    }

    func restart() async throws {
        _ = try await post("api/restart", [String: String](), as: PlayResponse.self, timeout: 10)
    }

    func log(lines: Int = 300) async throws -> String {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/log"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lines", value: String(lines))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ClientError(message: (try? JSONCoding.decoder.decode(APIError.self, from: data))?.error ?? "Log nicht lesbar")
        }
        return String(decoding: data, as: UTF8.self)
    }

    func backup() async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/backup"))
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClientError(message: String(localized: "Sicherung fehlgeschlagen")) }
        return data
    }

    func restore(_ data: Data) async throws -> ShowsResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/restore"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return try await send(request, as: ShowsResponse.self)
    }

    func control(_ action: PlayerAction) async throws -> PlayResponse {
        try await post("api/control", ControlRequest(action: action), as: PlayResponse.self, timeout: 10)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, _ body: Body, as type: T.Type,
                                                      timeout: TimeInterval) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encoder.encode(body)
        return try await send(request, as: type)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        var request = request
        // Meldungen des Servers in der Sprache der App
        request.setValue(AppSettings.languageCode, forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: String(localized: "Keine gültige Antwort vom Server"))
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONCoding.decoder.decode(APIError.self, from: data))?.error
            throw ClientError(message: message ?? "Server-Fehler \(http.statusCode)")
        }
        return try JSONCoding.decoder.decode(type, from: data)
    }
}

// MARK: - Übersetzung

/// Übersetzt einen gespeicherten deutschen Text für die Anzeige (z. B. Tastennamen wie „Leertaste“
/// oder die Sammlungen „Filme“ und „YouTube-Videos“). Unbekannte Texte bleiben unverändert.
func L(_ text: String) -> String {
    NSLocalizedString(text, comment: "")
}

extension Show {
    /// Name für die Anzeige – die vom Server angelegten Sammlungen werden übersetzt
    var displayName: String {
        id == Show.moviesID || id == Show.youtubeVideosID ? L(name) : name
    }
}

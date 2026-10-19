import Foundation
import VoiceCore

enum AppSettings {
    static let serverKey = "serverURL"
    /// Leer: die App sucht den Server per Bonjour (`ServerDiscovery`) und trägt ihn selbst ein
    static let defaultServer = ""
    static let pointerSpeedKey = "pointerSpeed"
    static let defaultPointerSpeed = 1.5
    static let showSortKey = "showSort"
    /// IDs der eingeklappten Shows in der Seitenleiste, durch Zeilenumbrüche getrennt
    static let collapsedShowsKey = "collapsedShows"
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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "Keine gültige Antwort vom Server")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONCoding.decoder.decode(APIError.self, from: data))?.error
            throw ClientError(message: message ?? "Server-Fehler \(http.statusCode)")
        }
        return try JSONCoding.decoder.decode(type, from: data)
    }
}

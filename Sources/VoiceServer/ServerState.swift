import Foundation
import VoiceCore

/// Gespeicherter Zustand des Servers: Shows, Folgenlisten und zuletzt gespielte Folgen.
/// Liegt auf dem Mac mini (daten.json), damit Mac-App und Web-App denselben Stand sehen.
actor ServerState {
    struct Catalog: Codable {
        var episodes: [Episode]
        var updatedAt: Date?
    }

    private struct Stored: Codable {
        var shows: [Show]
        var catalogs: [String: Catalog]
        var lastPlayed: EpisodeRef?
        var lastPlayedByShow: [String: String]
        /// Wann zuletzt eine Folge der Show gestartet wurde (fehlt in älteren Daten)
        var playedAt: [String: Date]?
    }

    private let file: URL
    private var data: Stored

    /// - Parameters:
    ///   - legacyFile: status.json der Version mit nur einer Show – wird beim ersten Start übernommen.
    ///   - defaultStartDelay: Wartezeit bis zur Start-Taste für die übernommene Show The Voice.
    init(file: URL, legacyFile: URL, defaultStartDelay: Double) {
        self.file = file
        if let saved = (try? Data(contentsOf: file)).flatMap({ try? JSONCoding.decoder.decode(Stored.self, from: $0) }) {
            data = saved
        } else {
            var theVoice = Show.theVoice
            theVoice.controls.startDelay = defaultStartDelay
            data = Stored(shows: [theVoice], catalogs: [:], lastPlayed: nil, lastPlayedByShow: [:])
            if let legacy = (try? Data(contentsOf: legacyFile))
                .flatMap({ try? JSONCoding.decoder.decode(CatalogResponse.self, from: $0) }) {
                data.catalogs[theVoice.id] = Catalog(episodes: legacy.episodes, updatedAt: legacy.updatedAt)
                if let id = legacy.lastPlayedID {
                    data.lastPlayed = EpisodeRef(show: theVoice.id, id: id)
                    data.lastPlayedByShow[theVoice.id] = id
                }
                serverLog("Alten Stand übernommen (status.json).")
            }
        }
    }

    // MARK: - Shows

    var showsResponse: ShowsResponse {
        ShowsResponse(shows: data.shows, lastPlayed: data.lastPlayed, playedAt: data.playedAt ?? [:])
    }

    var lastPlayed: EpisodeRef? { data.lastPlayed }

    func show(_ id: String) -> Show? {
        data.shows.first { $0.id == id }
    }

    /// Legt eine Show an oder ersetzt die mit derselben ID (Position bleibt erhalten).
    func upsert(_ show: Show) {
        if let index = data.shows.firstIndex(where: { $0.id == show.id }) {
            data.shows[index] = show
        } else {
            data.shows.append(show)
        }
        save()
    }

    func delete(_ id: String) {
        data.shows.removeAll { $0.id == id }
        data.catalogs[id] = nil
        data.lastPlayedByShow[id] = nil
        data.playedAt?[id] = nil
        if data.lastPlayed?.show == id { data.lastPlayed = nil }
        save()
    }

    /// Eigene Reihenfolge: Shows in der Reihenfolge der IDs, nicht genannte bleiben dahinter
    func reorder(_ ids: [String]) {
        let position = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func rank(_ index: Int, _ show: Show) -> Int { position[show.id] ?? ids.count + index }
        data.shows = data.shows.enumerated()
            .sorted { rank($0.offset, $0.element) < rank($1.offset, $1.element) }
            .map(\.element)
        save()
    }

    // MARK: - Folgen

    func catalog(for show: String) -> Catalog? {
        data.catalogs[show]
    }

    func setEpisodes(_ list: [Episode], for show: String) {
        data.catalogs[show] = Catalog(episodes: list, updatedAt: Date())
        save()
    }

    func response(for show: Show) -> CatalogResponse {
        let catalog = show.kind == .custom || show.kind == .movies
            ? Catalog(episodes: show.customEpisodes, updatedAt: nil)
            : data.catalogs[show.id] ?? Catalog(episodes: [], updatedAt: nil)
        return CatalogResponse(episodes: catalog.episodes, lastPlayedID: data.lastPlayedByShow[show.id],
                               updatedAt: catalog.updatedAt)
    }

    func setLastPlayed(_ ref: EpisodeRef) {
        data.lastPlayed = ref
        data.lastPlayedByShow[ref.show] = ref.id
        data.playedAt = (data.playedAt ?? [:]).merging([ref.show: Date()]) { _, new in new }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONCoding.encoder.encode(data).write(to: file, options: .atomic)
        } catch {
            serverLog("Status konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }
}

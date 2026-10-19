import SwiftUI
import VoiceCore

/// Sortierung der Shows in der Seitenleiste
enum ShowSort: String, CaseIterable, Identifiable {
    /// Wie unter Einstellungen → Shows angeordnet (wird auf dem Server gespeichert)
    case custom
    /// Zuletzt gesehene Show zuerst
    case recent
    /// Alphabetisch
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom: return "Eigene Reihenfolge"
        case .recent: return "Zuletzt gesehen"
        case .name: return "Name (A–Z)"
        }
    }

    var icon: String {
        switch self {
        case .custom: return "line.3.horizontal"
        case .recent: return "clock"
        case .name: return "textformat"
        }
    }
}

@MainActor
final class EpisodeModel: ObservableObject {
    @Published private(set) var shows: [Show] = []
    @Published private(set) var episodesByShow: [String: [Episode]] = [:]
    @Published private(set) var lastPlayedByShow: [String: String] = [:]
    /// Zuletzt gestartete Folge über alle Shows
    @Published private(set) var lastPlayedRef: EpisodeRef?
    /// Wann zuletzt eine Folge der Show gestartet wurde
    @Published private(set) var playedAt: [String: Date] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    /// `Episode.key` der Folge, die gerade gestartet wird
    @Published private(set) var playingKey: String?
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private var client: APIClient? { APIClient.fromSettings() }

    // MARK: - Abfragen

    func show(_ id: String) -> Show? { shows.first { $0.id == id } }

    /// Shows in der gewählten Sortierung (bei gleichem Rang gilt die eigene Reihenfolge)
    func sortedShows(_ sort: ShowSort) -> [Show] {
        switch sort {
        case .custom:
            return shows
        case .name:
            return shows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent:
            let order = Dictionary(uniqueKeysWithValues: shows.enumerated().map { ($1.id, $0) })
            // Ältere Daten ohne Zeitpunkte: die zuletzt gespielte Show zählt trotzdem als neueste
            var dates = playedAt
            if let last = lastPlayedRef?.show, dates[last] == nil {
                dates[last] = (dates.values.max() ?? .distantPast).addingTimeInterval(1)
            }
            return shows.sorted { a, b in
                switch (dates[a.id], dates[b.id]) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return order[a.id, default: 0] < order[b.id, default: 0]
                }
            }
        }
    }

    func episodes(for show: Show) -> [Episode] { episodesByShow[show.id] ?? [] }

    /// Gruppen einer Show in fester Reihenfolge (YouTube: Videos, Shorts), nur wenn vorhanden
    func groups(for show: Show) -> [String] {
        [Episode.videos, Episode.shorts].filter { !episodes(for: show, group: $0).isEmpty }
    }

    /// Folgen einer Gruppe; ältere Daten ohne Gruppe zählen als "Videos"
    func episodes(for show: Show, group: String) -> [Episode] {
        episodes(for: show).filter { ($0.group ?? Episode.videos) == group }
    }

    func seasons(for show: Show) -> [Int] {
        Array(Set(episodes(for: show).map(\.season))).sorted(by: >)
    }

    var allEpisodes: [Episode] { shows.flatMap { episodes(for: $0) } }

    var lastPlayed: Episode? {
        guard let ref = lastPlayedRef else { return nil }
        return episodesByShow[ref.show]?.first { $0.id == ref.id }
    }

    var lastPlayedShow: Show? { lastPlayedRef.flatMap { show($0.show) } }

    func isLastPlayed(_ episode: Episode) -> Bool { lastPlayedByShow[episode.show] == episode.id }

    func isPlaying(_ episode: Episode) -> Bool { playingKey == episode.key }

    var isBusy: Bool { playingKey != nil }

    /// Die Folge nach der zuletzt gespielten (in derselben Show, auch über die Staffelgrenze hinweg).
    var nextEpisode: Episode? {
        guard let last = lastPlayed else { return nil }
        let ordered = (episodesByShow[last.show] ?? []).sorted { ($0.season, $0.number) < ($1.season, $1.number) }
        guard let index = ordered.firstIndex(of: last), index + 1 < ordered.count else { return nil }
        return ordered[index + 1]
    }

    // MARK: - Laden

    func load(refresh: Bool = false) async {
        guard !isLoading else { return }
        guard let client = client else {
            errorMessage = "Noch kein Server gefunden. Läuft der TV-Launcher-Server am Mac am Fernseher? Adresse sonst in den Einstellungen (⌘,) eintragen."
            return
        }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            apply(try await client.shows())
        } catch {
            errorMessage = "Mac mini nicht erreichbar: \(error.localizedDescription)"
            return
        }
        // Folgen aller Shows parallel laden
        var failures: [String] = []
        await withTaskGroup(of: (String, Result<CatalogResponse, Error>).self) { group in
            for show in shows {
                let id = show.id
                group.addTask { (id, await Self.fetch(client, show: id, refresh: refresh)) }
            }
            for await (id, result) in group {
                switch result {
                case .success(let catalog):
                    episodesByShow[id] = catalog.episodes
                    lastPlayedByShow[id] = catalog.lastPlayedID
                case .failure(let error):
                    failures.append("\(show(id)?.name ?? id): \(error.localizedDescription)")
                }
            }
        }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private nonisolated static func fetch(_ client: APIClient, show: String,
                                          refresh: Bool) async -> Result<CatalogResponse, Error> {
        do {
            return .success(try await client.catalog(show: show, refresh: refresh))
        } catch {
            return .failure(error)
        }
    }

    private func apply(_ response: ShowsResponse) {
        shows = response.shows
        lastPlayedRef = response.lastPlayed
        playedAt = response.playedAt ?? playedAt
        let ids = Set(shows.map(\.id))
        episodesByShow = episodesByShow.filter { ids.contains($0.key) }
    }

    // MARK: - Shows verwalten (Einstellungen)

    func saveShow(_ show: Show) async throws {
        guard let client = client else { throw ClientError(message: "Ungültige Server-Adresse") }
        apply(try await client.saveShow(show))
        // Folgen im Hintergrund nachladen (neue Joyn-Shows brauchen beim ersten Mal etwas länger)
        let id = show.id
        Task {
            switch await Self.fetch(client, show: id, refresh: false) {
            case .success(let catalog):
                episodesByShow[id] = catalog.episodes
                lastPlayedByShow[id] = catalog.lastPlayedID
            case .failure(let error):
                errorMessage = "\(self.show(id)?.name ?? id): \(error.localizedDescription)"
            }
        }
    }

    /// Eigene Reihenfolge speichern
    func reorderShows(_ ids: [String]) async throws {
        guard let client = client else { throw ClientError(message: "Ungültige Server-Adresse") }
        // Sofort anzeigen, dann auf dem Server speichern
        let position = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        shows.sort { position[$0.id, default: .max] < position[$1.id, default: .max] }
        apply(try await client.reorderShows(ids))
    }

    /// Show in der eigenen Reihenfolge um `offset` Plätze verschieben (−1 = nach oben)
    func moveShow(_ id: String, by offset: Int) async {
        guard let index = shows.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), shows.count - 1)
        guard target != index else { return }
        var ids = shows.map(\.id)
        ids.insert(ids.remove(at: index), at: target)
        do {
            try await reorderShows(ids)
        } catch {
            errorMessage = "Reihenfolge nicht gespeichert: \(error.localizedDescription)"
        }
    }

    func deleteShow(_ id: String) async throws {
        guard let client = client else { throw ClientError(message: "Ungültige Server-Adresse") }
        apply(try await client.deleteShow(id))
    }

    /// Joyn-Film merken und auf Wunsch sofort am Mac mini starten
    func addMovie(_ movie: String, play: Bool) async throws {
        guard let client = client else { throw ClientError(message: "Ungültige Server-Adresse") }
        let response = try await client.movie(movie, play: play)
        apply(try await client.shows())
        let catalog = try await client.catalog(show: Show.moviesID, refresh: false)
        episodesByShow[Show.moviesID] = catalog.episodes
        lastPlayedByShow[Show.moviesID] = catalog.lastPlayedID
        showStatus(response.message)
    }

    // MARK: - Abspielen & Steuern

    func play(_ episode: Episode) async {
        guard playingKey == nil, let client = client else { return }
        playingKey = episode.key
        defer { playingKey = nil }
        do {
            let response = try await client.play(episode)
            lastPlayedRef = EpisodeRef(show: episode.show, id: episode.id)
            lastPlayedByShow[episode.show] = episode.id
            playedAt[episode.show] = Date()
            showStatus(response.message)
            errorMessage = nil
        } catch {
            errorMessage = "Abspielen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func control(_ action: PlayerAction) async {
        guard let client = client else { return }
        do {
            let response = try await client.control(action)
            showStatus(response.message)
            errorMessage = nil
        } catch {
            errorMessage = "Steuerung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Zeigt eine Meldung in der Player-Leiste und blendet sie nach ein paar Sekunden aus.
    private func showStatus(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if statusMessage == message { statusMessage = nil }
        }
    }
}

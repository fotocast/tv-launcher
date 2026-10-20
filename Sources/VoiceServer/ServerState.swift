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
        /// Stand der Tastenbelegungen: 1 = Untertitel-Taste für YouTube ergänzt
        var controlsVersion: Int?
        /// Eigene Tasten-Presets
        var presets: [KeyPreset]?
        /// Einstellungen des Servers (fehlt in älteren Daten → Standard)
        var settings: ServerSettings?
    }

    private let file: URL
    private var data: Stored

    /// - Parameters:
    ///   - legacyFile: status.json der Version mit nur einer Show – wird beim ersten Start übernommen.
    ///   - defaultStartDelay: Wartezeit bis zur Start-Taste für die übernommene Show The Voice.
    init(file: URL, legacyFile: URL, defaultStartDelay: Double) {
        self.file = file
        if let saved = (try? Data(contentsOf: file)).flatMap({ try? JSONCoding.decoder.decode(Stored.self, from: $0) }) {
            data = Self.migrated(saved)
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

    /// Ältere Daten: YouTube-Shows bekommen Untertitel (C) und Lautstärke-Tasten (↑/↓/M) – wird beim nächsten Speichern gesichert
    private static func migrated(_ stored: Stored) -> Stored {
        var stored = stored
        guard (stored.controlsVersion ?? 0) < 2 else { return stored }
        for index in stored.shows.indices
        where stored.shows[index].kind == .youtube || stored.shows[index].id == Show.youtubeVideosID {
            var controls = stored.shows[index].controls
            let youtube = ShowControls.youtubeDefault
            if controls.subtitles.kind == .none { controls.subtitles = youtube.subtitles }
            if controls.volumeUp.kind == .none { controls.volumeUp = youtube.volumeUp }
            if controls.volumeDown.kind == .none { controls.volumeDown = youtube.volumeDown }
            if controls.mute.kind == .none { controls.mute = youtube.mute }
            stored.shows[index].controls = controls
        }
        stored.controlsVersion = 2
        return stored
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

    /// Ordner umbenennen bzw. auflösen (`to` = nil)
    func renameFolder(_ from: String, to: String?) {
        for index in data.shows.indices where data.shows[index].folder == from {
            data.shows[index].folder = to
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
        let catalog = show.isLinkCollection
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

    /// „Zuletzt gespielt“ einer Show vergessen (Verlauf löschen). `lastPlayed` bleibt, damit die
    /// Fernbedienung weiter die Tasten der laufenden Show nutzt.
    func forgetPlayed(show: String) {
        data.lastPlayedByShow[show] = nil
        save()
    }

    // MARK: - Einstellungen & Sicherung

    var settings: ServerSettings { data.settings ?? ServerSettings() }

    func setSettings(_ settings: ServerSettings) {
        data.settings = settings.clamped
        save()
    }

    var backup: BackupFile {
        BackupFile(shows: data.shows, presets: data.presets ?? [], settings: settings)
    }

    /// Ersetzt Shows, eigene Presets und Einstellungen. Zwischengespeicherte Folgen bleiben für Shows, die es weiter gibt.
    func restore(_ backup: BackupFile) {
        data.shows = backup.shows
        data.presets = backup.presets.filter { !$0.isBuiltIn }
        data.settings = backup.settings.clamped
        let ids = Set(backup.shows.map(\.id))
        data.catalogs = data.catalogs.filter { ids.contains($0.key) }
        data.lastPlayedByShow = data.lastPlayedByShow.filter { ids.contains($0.key) }
        if let last = data.lastPlayed, !ids.contains(last.show) { data.lastPlayed = nil }
        save()
    }

    // MARK: - Tasten-Presets

    /// Eingebaute Vorlagen zuerst, dann die eigenen
    var presetsResponse: PresetsResponse {
        PresetsResponse(presets: KeyPreset.builtIns + (data.presets ?? []))
    }

    /// Legt ein Preset an; ein eigenes Preset mit gleichem Namen wird ersetzt.
    func savePreset(_ preset: KeyPreset) {
        var list = data.presets ?? []
        var preset = preset
        preset.builtIn = nil
        if let index = list.firstIndex(where: {
            $0.id == preset.id || $0.name.localizedCaseInsensitiveCompare(preset.name) == .orderedSame
        }) {
            preset.id = list[index].id
            list[index] = preset
        } else {
            list.append(preset)
        }
        data.presets = list
        save()
    }

    func deletePreset(_ id: String) {
        data.presets?.removeAll { $0.id == id }
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

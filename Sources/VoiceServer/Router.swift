import Foundation
import ApplicationServices
import CoreGraphics
import VoiceCore

/// Hält für jede Joyn-Serie einen eigenen Katalog (mit eigenem Cache).
actor CatalogStore {
    private let dataDir: URL
    private var catalogs: [String: JoynCatalog] = [:]

    init(dataDir: URL) {
        self.dataDir = dataDir
    }

    func catalog(for series: String) -> JoynCatalog {
        if let catalog = catalogs[series] { return catalog }
        // The Voice behält den Dateinamen aus der ersten Version
        let name = series == Episode.series ? "bekannte-folgen.json" : "joyn-\(series).json"
        let catalog = JoynCatalog(series: series, cacheFile: dataDir.appendingPathComponent(name),
                                  logger: { serverLog($0) })
        catalogs[series] = catalog
        return catalog
    }
}

final class Router: @unchecked Sendable {
    private let catalogs: CatalogStore
    private let state: ServerState
    private let config: ServerConfig
    private let autoPlay = AutoPlay()
    private let remoteInput = RemoteInput()
    private let youtube = YouTube()
    private let sleepTimer = SleepTimer()
    private let startedAt = Date()
    /// Nach dieser Zeit wird eine Joyn-Liste beim nächsten Abruf neu von joyn.de geladen.
    private let refreshInterval: TimeInterval = 3 * 3600

    init(catalogs: CatalogStore, state: ServerState, config: ServerConfig) {
        self.catalogs = catalogs
        self.state = state
        self.config = config
    }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let response = await route(request)
        return ServerI18n.wantsEnglish(request) ? ServerI18n.translate(response) : response
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            return HTTPResponse(status: 204, contentType: "text/plain", body: Data())
        case ("GET", "/api/health"):
            return .json(["ok": true])
        case ("GET", "/api/shows"):
            return .json(await state.showsResponse)
        case ("POST", "/api/shows"):
            return await saveShow(request)
        case ("GET", "/api/settings"):
            return .json(await state.settings)
        case ("POST", "/api/settings"):
            return await saveSettings(request)
        case ("GET", "/api/status"):
            return .json(await status())
        case ("GET", "/api/log"):
            return log(lines: Int(request.queryValue("lines") ?? "") ?? 300)
        case ("POST", "/api/restart"):
            serverLog("Neustart angefordert – der Dienst startet gleich neu.")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { exit(0) }   // launchd startet neu (KeepAlive)
            return .json(PlayResponse(ok: true, message: "Server startet neu …"))
        case ("GET", "/api/volume"):
            return .json(Player.volume() ?? VolumeResponse(volume: nil, muted: nil))
        case ("POST", "/api/volume"):
            return await volume(request)
        case ("POST", "/api/sleep"):
            return await sleep(request)
        case ("GET", "/api/backup"):
            var response = HTTPResponse.json(await state.backup)
            let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
            response.headers["Content-Disposition"] = "attachment; filename=\"TV-Launcher-Sicherung-\(day).json\""
            return response
        case ("POST", "/api/restore"):
            return await restore(request)
        case ("GET", "/api/presets"):
            return .json(await state.presetsResponse)
        case ("POST", "/api/presets"):
            guard var preset = try? JSONCoding.decoder.decode(PresetRequest.self, from: request.body).preset else {
                return .error("Erwartet wird {\"preset\": {\"name\", \"controls\"}}", status: 400)
            }
            preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !preset.name.isEmpty else { return .error("Das Preset braucht einen Namen.", status: 400) }
            if KeyPreset.builtIns.contains(where: {
                $0.id == preset.id || $0.name.localizedCaseInsensitiveCompare(preset.name) == .orderedSame
            }) {
                return .error("„\(preset.name)“ ist eine eingebaute Vorlage – bitte einen anderen Namen wählen.", status: 400)
            }
            if preset.id.isEmpty || preset.id.hasPrefix("builtin-") {
                preset.id = "preset-" + UUID().uuidString.lowercased().prefix(8)
            }
            await state.savePreset(preset)
            serverLog("Tasten-Preset gesichert: \(preset.name)")
            return .json(await state.presetsResponse)
        case ("POST", "/api/presets/delete"):
            guard let body = try? JSONCoding.decoder.decode(DeleteShowRequest.self, from: request.body) else {
                return .error("Erwartet wird {\"id\": \"<Preset>\"}", status: 400)
            }
            await state.deletePreset(body.id)
            return .json(await state.presetsResponse)
        case ("POST", "/api/shows/add"):
            return await addShow(request)
        case ("POST", "/api/shows/delete"):
            return await deleteShow(request)
        case ("POST", "/api/shows/order"):
            guard let body = try? JSONCoding.decoder.decode(ShowOrderRequest.self, from: request.body) else {
                return .error("Erwartet wird {\"ids\": [...]}", status: 400)
            }
            await state.reorder(body.ids)
            return .json(await state.showsResponse)
        case ("GET", "/api/episodes"):
            return await episodes(showID: request.queryValue("show") ?? Episode.series, force: false)
        case ("POST", "/api/refresh"):
            return await episodes(showID: request.queryValue("show") ?? Episode.series, force: true)
        case ("POST", "/api/play"):
            return await play(request)
        case ("POST", "/api/movies"):
            return await movie(request)
        case ("GET", "/api/youtube/search"):
            return await youtubeSearch(request.queryValue("q") ?? "")
        case ("POST", "/api/youtube/clear"):
            // Verlauf der einzeln gestarteten YouTube-Videos löschen
            if var collection = await state.show(Show.youtubeVideosID) {
                collection.links = []
                await state.upsert(collection)
            }
            await state.forgetPlayed(show: Show.youtubeVideosID)
            serverLog("YouTube-Verlauf gelöscht")
            return .json(await state.showsResponse)
        case ("POST", "/api/youtube"):
            return await youtubeVideo(request)
        case ("POST", "/api/control"):
            return await control(request)
        case ("GET", "/api/screenshot"):
            do {
                return HTTPResponse(status: 200, contentType: "image/jpeg", body: try Screen.capture())
            } catch {
                return .error(error.localizedDescription, status: 500)
            }
        case ("POST", "/api/input"):
            return await input(request)
        case ("GET", _):
            return staticFile(request.path)
        default:
            return .error("Nicht gefunden", status: 404)
        }
    }

    // MARK: - Shows

    private func saveShow(_ request: HTTPRequest) async -> HTTPResponse {
        guard let show = try? JSONCoding.decoder.decode(ShowRequest.self, from: request.body).show else {
            return .error("Erwartet wird {\"show\": {...}}", status: 400)
        }
        return await save(show)
    }

    /// Neue Show aus einer Adresse (Web-App)
    private func addShow(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(AddShowRequest.self, from: request.body) else {
            return .error("Erwartet wird {\"kind\", \"input\", \"name\"}", status: 400)
        }
        let input = (body.input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (body.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch body.kind {
        case .joyn:
            let url = URL(string: input.contains("://") ? input : "https://www.joyn.de/serien/\(input)")
            guard let slug = url.flatMap(Show.joynSeries(in:)) else {
                return .error("Keine Joyn-Serie erkannt. Erwartet wird eine Adresse wie joyn.de/serien/…", status: 400)
            }
            if let existing = await state.show(slug) {
                return .error("„\(existing.name)“ ist schon vorhanden.", status: 400)
            }
            guard let info = await Self.joynSeriesInfo(slug) else {
                return .error("Die Serie „\(slug)“ wurde auf joyn.de nicht gefunden.", status: 400)
            }
            var show = Show.joyn(series: slug, name: name.isEmpty ? info.name ?? Self.humanized(slug) : name)
            show.image = info.image
            return await save(show)
        case .youtube:
            guard !input.isEmpty else { return .error("Bitte eine Kanal-Adresse oder @Name eingeben.", status: 400) }
            return await save(Show.youtube(channel: input, name: name))
        case .custom:
            return await save(Show.custom(name: name.isEmpty ? "Neue Show" : name))
        case .movies:
            return .error("Filme bitte über /api/movies hinzufügen.", status: 400)
        }
    }

    private static func humanized(_ slug: String) -> String {
        slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private func save(_ show: Show) async -> HTTPResponse {
        var show = show
        show.name = show.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if show.kind == .youtube {
            // Kanal-Adresse oder @Name in die Kanal-ID umwandeln, Name und Bild übernehmen
            guard show.id.hasPrefix("youtube-"), let input = show.channel, !input.isEmpty else {
                return .error("Für einen YouTube-Kanal fehlt die Kanal-Adresse.", status: 400)
            }
            do {
                let channel = try await youtube.resolveChannel(input)
                if let other = await state.showsResponse.shows.first(where: {
                    $0.kind == .youtube && $0.channel == channel.id && $0.id != show.id
                }) {
                    return .error("Dieser Kanal ist schon als „\(other.name)“ hinzugefügt.", status: 400)
                }
                show.channel = channel.id
                show.image = channel.image ?? show.image
                if show.name.isEmpty { show.name = channel.name }
            } catch {
                return .error(error.localizedDescription, status: 400)
            }
            show.links = []
        }
        guard !show.name.isEmpty else { return .error("Die Show braucht einen Namen.", status: 400) }
        switch show.kind {
        case .youtube:
            break
        case .joyn:
            guard show.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else {
                return .error("Ungültige Joyn-Serie „\(show.id)“.", status: 400)
            }
            show.links = []
            if show.image == nil { show.image = await Self.joynSeriesImage(show.id) }
        case .custom, .movies:
            guard show.kind == .movies ? show.id == Show.moviesID : show.id.hasPrefix("custom-") else {
                return .error("Ungültige Show-ID.", status: 400)
            }
            show.links = show.links.map { link in
                var link = link
                link.url = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
                link.title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return link
            }
            for link in show.links {
                guard let url = URL(string: link.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    return .error("Ungültiger Link: „\(link.url)“ (muss mit http:// oder https:// beginnen).",
                                  status: 400)
                }
            }
        }
        await state.upsert(show)
        serverLog("Show gespeichert: \(show.name) (\(show.id))")
        return .json(await state.showsResponse)
    }

    private func deleteShow(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(DeleteShowRequest.self, from: request.body) else {
            return .error("Erwartet wird {\"id\": \"<Show>\"}", status: 400)
        }
        await state.delete(body.id)
        serverLog("Show gelöscht: \(body.id)")
        return .json(await state.showsResponse)
    }

    // MARK: - Folgen

    private func episodes(showID: String, force: Bool) async -> HTTPResponse {
        guard let show = await state.show(showID) else { return .error("Unbekannte Show", status: 404) }
        switch show.kind {
        case .custom, .movies: return .json(await state.response(for: show))
        case .youtube: return await youtubeEpisodes(show, force: force)
        case .joyn: break
        }

        let settings = await state.settings
        let stored = await state.catalog(for: show.id)
        let isEmpty = stored?.episodes.isEmpty ?? true
        let isStale = stored?.updatedAt.map { Date().timeIntervalSince($0) > refreshInterval } ?? true
        if force || isStale || isEmpty {
            let catalog = await catalogs.catalog(for: show.id)
            do {
                await state.setEpisodes(try await catalog.refresh(seasonCount: settings.joynSeasons), for: show.id)
            } catch {
                serverLog("\(show.id): Aktualisierung fehlgeschlagen: \(error.localizedDescription)")
                if isEmpty {
                    let cached = await catalog.cachedSelection(seasonCount: settings.joynSeasons)
                    if cached.isEmpty {
                        return .error("Folgen konnten nicht von joyn.de geladen werden: \(error.localizedDescription)",
                                      status: 502)
                    }
                    await state.setEpisodes(cached, for: show.id)
                }
            }
        }
        return .json(await state.response(for: show))
    }

    /// YouTube: die neuesten Videos, neu geladen im eingestellten Abstand (Standard 30 Minuten)
    private func youtubeEpisodes(_ show: Show, force: Bool) async -> HTTPResponse {
        guard let channel = show.channel else { return .error("Kanal fehlt", status: 500) }
        let stored = await state.catalog(for: show.id)
        let isEmpty = stored?.episodes.isEmpty ?? true
        let interval = Double(await state.settings.youtubeRefreshMinutes) * 60
        let isStale = stored?.updatedAt.map { Date().timeIntervalSince($0) > interval } ?? true
        if force || isStale || isEmpty {
            do {
                let videos = try await youtube.videos(channelID: channel, show: show.id)
                await state.setEpisodes(videos, for: show.id)
                serverLog("\(show.name): \(videos.count) YouTube-Videos geladen")
            } catch {
                serverLog("\(show.name): YouTube-Aktualisierung fehlgeschlagen: \(error.localizedDescription)")
                if isEmpty { return .error(error.localizedDescription, status: 502) }
            }
        }
        return .json(await state.response(for: show))
    }

    // MARK: - Abspielen & Steuern

    private func play(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(PlayRequest.self, from: request.body) else {
            return .error("Erwartet wird {\"show\": \"<Show>\", \"id\": \"<Folge>\"}", status: 400)
        }
        guard let show = await state.show(body.show ?? Episode.series) else {
            return .error("Unbekannte Show", status: 404)
        }
        // Nur Folgen aus der Liste sind erlaubt
        guard let episode = await state.response(for: show).episodes.first(where: { $0.id == body.id }) else {
            return .error("Unbekannte Folge", status: 404)
        }
        return await start(episode, of: show)
    }

    /// Öffnet die Folge im Browser und drückt danach die Start-Taste der Show.
    private func start(_ episode: Episode, of show: Show) async -> HTTPResponse {
        guard let url = episode.playURL else { return .error("Ungültige Adresse", status: 400) }
        do {
            await autoPlay.cancel()
            try Player.open(url, browser: config.browser, closeOldTabs: config.closeOldTabs)
            await state.setLastPlayed(EpisodeRef(show: show.id, id: episode.id))
            serverLog("Spiele \(show.name): \(episode.code) \(episode.title)")
            let settings = await state.settings
            if let volume = settings.startVolume { Player.setVolume(volume) }
            // Start-Taste nach der Wartezeit, danach auf Wunsch Vollbild
            var steps: [(KeyBinding, Double)] = [(show.controls.start, show.controls.startDelay)]
            if settings.autoFullscreen, show.controls.fullscreen.kind != .none {
                let wait = show.controls.start.kind == .none
                    ? show.controls.startDelay + settings.fullscreenDelay : settings.fullscreenDelay
                steps.append((show.controls.fullscreen, wait))
            }
            if steps.contains(where: { $0.0.kind != .none }) {
                let (autoPlay, browser) = (self.autoPlay, config.browser)
                Task { await autoPlay.sequence(steps, browser: browser) }
            } else {
                await autoPlay.cancel()
            }
            let name = show.kind == .movies ? episode.title : "\(episode.code) · \(episode.title)"
            return .json(PlayResponse(ok: true, message: "\(name) läuft auf dem Mac mini"))
        } catch {
            return .error("Browser konnte nicht geöffnet werden: \(error.localizedDescription)", status: 500)
        }
    }

    // MARK: - Filme

    /// Merkt einen Joyn-Film in der Sammlung "Filme" (legt sie bei Bedarf an) und startet ihn auf Wunsch.
    private func movie(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(MovieRequest.self, from: request.body) else {
            return .error("Erwartet wird {\"movie\": \"<Joyn-Film>\", \"play\": true}", status: 400)
        }
        let input = body.movie.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = URL(string: input).flatMap(Show.joynMovie(in:))
            ?? (input.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil ? input : nil)
        guard let slug else { return .error("Kein Joyn-Film erkannt: „\(input)“", status: 400) }

        var collection = await state.show(Show.moviesID) ?? Show.movies
        if !collection.links.contains(where: { $0.id == slug }) {
            let info = await Self.movieInfo(slug)
            guard let info else { return .error("Film „\(slug)“ auf joyn.de nicht gefunden.", status: 404) }
            // Zuletzt hinzugefügte Filme zuerst
            collection.links.insert(ShowLink(id: slug, title: info.title, url: Show.joynMoviePlayURL(slug),
                                             image: info.image), at: 0)
            await state.upsert(collection)
            serverLog("Film gemerkt: \(info.title)")
        }
        guard body.play else {
            let title = collection.links.first { $0.id == slug }?.title ?? slug
            return .json(PlayResponse(ok: true, message: "„\(title)“ zu Filmen hinzugefügt"))
        }
        guard let episode = collection.customEpisodes.first(where: { $0.id == slug }) else {
            return .error("Film nicht gefunden", status: 404)
        }
        return await start(episode, of: collection)
    }

    // MARK: - Einzelne YouTube-Videos

    /// Merkt ein YouTube-Video in der Sammlung "YouTube-Videos" (legt sie bei Bedarf an) und startet es auf Wunsch.
    private func youtubeVideo(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(YouTubeVideoRequest.self, from: request.body) else {
            return .error("Erwartet wird {\"video\": \"<YouTube-Link>\", \"play\": true}", status: 400)
        }
        guard let id = Show.youtubeVideoID(in: body.video) else {
            return .error("Kein YouTube-Video erkannt: „\(body.video)“", status: 400)
        }
        var collection = await state.show(Show.youtubeVideosID) ?? Show.youtubeVideos
        // Zuletzt gestartete Videos zuerst, höchstens 50 behalten
        let existing = collection.links.first { $0.id == id }
        collection.links.removeAll { $0.id == id }
        let link: ShowLink
        if let existing {
            link = existing
        } else {
            let info = await Self.youtubeInfo(id)
            link = ShowLink(id: id, title: info?.title ?? "YouTube-Video", url: "https://www.youtube.com/watch?v=\(id)",
                            image: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg", note: info?.channel)
        }
        collection.links.insert(link, at: 0)
        collection.links = Array(collection.links.prefix(50))
        await state.upsert(collection)
        guard body.play else {
            return .json(PlayResponse(ok: true, message: "„\(link.title)“ zu YouTube-Videos hinzugefügt"))
        }
        guard let episode = collection.customEpisodes.first(where: { $0.id == id }) else {
            return .error("Video nicht gefunden", status: 404)
        }
        return await start(episode, of: collection)
    }

    /// Titel und Kanal eines YouTube-Videos (oEmbed, ohne Schlüssel)
    private static func youtubeInfo(_ id: String) async -> (title: String, channel: String?)? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
                                 URLQueryItem(name: "format", value: "json")]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else { return nil }
        return (title, json["author_name"] as? String)
    }

    /// Titelbild einer Joyn-Serie (og:image der Serienseite, Querformat)
    static func joynSeriesImage(_ slug: String) async -> String? {
        await joynSeriesInfo(slug)?.image
    }

    /// Name und Titelbild einer Joyn-Serie von ihrer Seite.
    /// og:title lautet z. B. 'Ganze Folgen von "Germany's Next Topmodel" kostenlos online streamen | Joyn'.
    /// `nil`, wenn es die Serienseite nicht gibt.
    static func joynSeriesInfo(_ slug: String) async -> (name: String?, image: String?)? {
        guard let url = URL(string: "https://www.joyn.de/serien/\(slug)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(JoynCatalog.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let image = JoynCatalog.matches(of: #"<meta property="og:image" content="([^"]*)""#, in: html).first
            .map(YouTube.decodeEntities)
        let title = JoynCatalog.matches(of: #"<meta property="og:title" content="([^"]*)""#, in: html).first
            .map(YouTube.decodeEntities)
        var name: String?
        if let title, let start = title.firstIndex(of: "\""),
           let end = title[title.index(after: start)...].firstIndex(of: "\"") {
            name = String(title[title.index(after: start)..<end])
        }
        return (name?.isEmpty == false ? name : nil, image)
    }

    /// Ältere Joyn-Shows ohne Titelbild nachträglich ergänzen
    func fillMissingImages() async {
        for show in await state.showsResponse.shows where show.kind == .joyn && show.image == nil {
            guard let image = await Self.joynSeriesImage(show.id),
                  var current = await state.show(show.id), current.image == nil else { continue }
            current.image = image
            await state.upsert(current)
            serverLog("Titelbild ergänzt: \(show.name)")
        }
    }

    /// Titel und Titelbild eines Joyn-Films von seiner Seite
    private static func movieInfo(_ slug: String) async -> (title: String, image: String?)? {
        guard let url = URL(string: "https://www.joyn.de/filme/\(slug)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(JoynCatalog.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let title = JoynCatalog.matches(of: #"<meta property="og:title" content="([^"]*)""#, in: html).first
            .map(YouTube.decodeEntities)
        let image = JoynCatalog.matches(of: #"<meta property="og:image" content="([^"]*)""#, in: html).first
            .map(YouTube.decodeEntities)
        let fallback = slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return (title ?? fallback, image)
    }

    /// YouTube durchsuchen (Web-App); Kanäle, die schon Shows sind, werden markiert
    private func youtubeSearch(_ query: String) async -> HTTPResponse {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .error("Suchbegriff fehlt", status: 400) }
        do {
            var result = try await youtube.search(query)
            let added = Set(await state.showsResponse.shows.compactMap { $0.kind == .youtube ? $0.channel : nil })
            for index in result.channels.indices { result.channels[index].added = added.contains(result.channels[index].id) }
            return .json(result)
        } catch {
            return .error("YouTube-Suche fehlgeschlagen: \(error.localizedDescription)", status: 502)
        }
    }

    // MARK: - Einstellungen, Status & Wartung

    private func saveSettings(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(SettingsRequest.self, from: request.body) else {
            return .error("Erwartet wird {\"settings\": {...}}", status: 400)
        }
        let old = await state.settings
        await state.setSettings(body.settings)
        let new = await state.settings
        serverLog("Einstellungen gesichert")
        // Andere Staffelzahl: Joyn-Serien im Hintergrund neu laden
        if new.joynSeasons != old.joynSeasons {
            Task {
                for show in await state.showsResponse.shows where show.kind == .joyn {
                    _ = await episodes(showID: show.id, force: true)
                }
            }
        }
        return .json(new)
    }

    private func status() async -> ServerStatus {
        let volume = Player.volume()
        return ServerStatus(version: TVLauncher.version, host: ProcessInfo.processInfo.hostName,
                            browser: config.browser, closeOldTabs: config.closeOldTabs,
                            accessibility: AXIsProcessTrusted(), screenRecording: CGPreflightScreenCaptureAccess(),
                            startedAt: startedAt, volume: volume?.volume, muted: volume?.muted,
                            sleepAt: await sleepTimer.endsAt)
    }

    /// Die letzten Zeilen des Server-Logs
    private func log(lines: Int) -> HTTPResponse {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TheVoiceServer.log")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return .error("Log nicht gefunden: \(file.path)", status: 404)
        }
        let tail = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(min(max(lines, 10), 2000))
        return HTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", body: Data(tail.joined(separator: "\n").utf8))
    }

    private func volume(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(VolumeRequest.self, from: request.body) else {
            return .error("Erwartet wird {\"action\": \"up|down|mute|set\", \"value\": 0…100}", status: 400)
        }
        guard let current = Player.volume(), let level = current.volume, let muted = current.muted else {
            // Ton über HDMI: macOS kann nicht regeln → Lautstärke-Tasten des Players der laufenden Show
            let showID = await state.lastPlayed?.show ?? Episode.series
            let show = await state.show(showID) ?? Show.theVoice
            let binding: KeyBinding
            switch body.action {
            case "up": binding = show.controls.volumeUp
            case "down": binding = show.controls.volumeDown
            case "mute": binding = show.controls.mute
            default: binding = .none
            }
            guard binding.kind != .none else {
                return .error("Der Ton läuft über HDMI – die Lautstärke lässt sich am Mac nicht regeln, und \(show.name) hat "
                              + "keine Lautstärke-Taste. Bitte die Fernbedienung des Fernsehers nutzen.", status: 400)
            }
            do {
                try Player.perform(binding, browser: config.browser)
            } catch {
                return .error(error.localizedDescription, status: 500)
            }
            return .json(VolumeResponse(volume: nil, muted: nil, message: "Lautstärke im Player (\(binding.label))"))
        }
        Player.wakeDisplay()
        switch body.action {
        case "up": Player.setVolume(level + 6)
        case "down": Player.setVolume(level - 6)
        case "mute": Player.setMuted(!muted)
        case "set": Player.setVolume(body.value ?? level)
        default: return .error("Unbekannte Aktion „\(body.action)“", status: 400)
        }
        guard let now = Player.volume() else { return .error("Lautstärke nicht lesbar", status: 500) }
        return .json(now)
    }

    private func sleep(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(SleepRequest.self, from: request.body) else {
            return .error("Erwartet wird {\"minutes\": 30}", status: 400)
        }
        let (state, browser) = (self.state, config.browser)
        await sleepTimer.start(minutes: body.minutes) {
            serverLog("Sleep-Timer abgelaufen: Pause und Display aus")
            if let last = await state.lastPlayed, let show = await state.show(last.show) {
                try? Player.perform(show.controls.playPause, browser: browser)
            }
            Player.displaySleep()
        }
        serverLog(body.minutes > 0 ? "Sleep-Timer: \(body.minutes) Min." : "Sleep-Timer aus")
        return .json(await status())
    }

    private func restore(_ request: HTTPRequest) async -> HTTPResponse {
        guard let backup = try? JSONCoding.decoder.decode(BackupFile.self, from: request.body),
              backup.app == "TV Launcher" else {
            return .error("Keine gültige TV-Launcher-Sicherung", status: 400)
        }
        await state.restore(backup)
        serverLog("Sicherung eingespielt: \(backup.shows.count) Shows, \(backup.presets.count) Presets")
        // Folgen der Shows im Hintergrund laden
        Task {
            for show in await state.showsResponse.shows where show.kind != .custom {
                _ = await episodes(showID: show.id, force: false)
            }
        }
        return .json(await state.showsResponse)
    }

    private func control(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? JSONCoding.decoder.decode(ControlRequest.self, from: request.body) else {
            let actions = PlayerAction.allCases.map(\.rawValue).joined(separator: ", ")
            return .error("Erwartet wird {\"action\": \"…\"} mit einem von: \(actions)", status: 400)
        }
        // Tasten der Show, die zuletzt gestartet wurde
        let showID = await state.lastPlayed?.show ?? Episode.series
        let show = await state.show(showID) ?? Show.theVoice
        let binding = show.controls.binding(for: body.action)
        await autoPlay.cancel()
        do {
            guard binding.kind != .none else {
                throw Player.NoBindingError(action: body.action.label, show: show.name)
            }
            try Player.perform(binding, browser: config.browser)
            return .json(PlayResponse(ok: true, message: "\(body.action.label) (\(binding.label))"))
        } catch {
            return .error(error.localizedDescription, status: 500)
        }
    }

    private func input(_ request: HTTPRequest) async -> HTTPResponse {
        guard let batch = try? JSONCoding.decoder.decode(InputBatch.self, from: request.body) else {
            return .error("Erwartet wird {\"events\": [...]}", status: 400)
        }
        await autoPlay.cancel()
        do {
            try await remoteInput.apply(batch.events)
            return .json(PlayResponse(ok: true, message: "\(batch.events.count) Eingaben"))
        } catch {
            return .error(error.localizedDescription, status: 500)
        }
    }

    // MARK: - Web-App (Dateien aus dem Ordner Public)

    private func staticFile(_ path: String) -> HTTPResponse {
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else {
            return .error("Nicht erlaubt", status: 403)
        }
        var url = config.publicDir
        for component in components { url.appendPathComponent(component) }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            url.appendPathComponent("index.html")
        }
        guard let data = try? Data(contentsOf: url) else {
            return .error("Nicht gefunden", status: 404)
        }
        return HTTPResponse(status: 200, contentType: Self.mimeType(for: url.pathExtension), body: data)
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json", "webmanifest": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "ico": return "image/x-icon"
        default: return "application/octet-stream"
        }
    }
}

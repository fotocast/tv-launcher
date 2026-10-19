import Foundation
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
    /// Nach dieser Zeit wird eine Joyn-Liste beim nächsten Abruf neu von joyn.de geladen.
    private let refreshInterval: TimeInterval = 3 * 3600

    init(catalogs: CatalogStore, state: ServerState, config: ServerConfig) {
        self.catalogs = catalogs
        self.state = state
        self.config = config
    }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            return HTTPResponse(status: 204, contentType: "text/plain", body: Data())
        case ("GET", "/api/health"):
            return .json(["ok": true])
        case ("GET", "/api/shows"):
            return .json(await state.showsResponse)
        case ("POST", "/api/shows"):
            return await saveShow(request)
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
        guard var show = try? JSONCoding.decoder.decode(ShowRequest.self, from: request.body).show else {
            return .error("Erwartet wird {\"show\": {...}}", status: 400)
        }
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

        let stored = await state.catalog(for: show.id)
        let isEmpty = stored?.episodes.isEmpty ?? true
        let isStale = stored?.updatedAt.map { Date().timeIntervalSince($0) > refreshInterval } ?? true
        if force || isStale || isEmpty {
            let catalog = await catalogs.catalog(for: show.id)
            do {
                await state.setEpisodes(try await catalog.refresh(), for: show.id)
            } catch {
                serverLog("\(show.id): Aktualisierung fehlgeschlagen: \(error.localizedDescription)")
                if isEmpty {
                    let cached = await catalog.cachedSelection()
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

    /// YouTube: die neuesten Videos, alle 30 Minuten neu geladen
    private func youtubeEpisodes(_ show: Show, force: Bool) async -> HTTPResponse {
        guard let channel = show.channel else { return .error("Kanal fehlt", status: 500) }
        let stored = await state.catalog(for: show.id)
        let isEmpty = stored?.episodes.isEmpty ?? true
        let isStale = stored?.updatedAt.map { Date().timeIntervalSince($0) > 30 * 60 } ?? true
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
            try Player.open(url, browser: config.browser)
            await state.setLastPlayed(EpisodeRef(show: show.id, id: episode.id))
            serverLog("Spiele \(show.name): \(episode.code) \(episode.title)")
            let start = show.controls.start
            if start.kind != .none {
                let (autoPlay, delay, browser) = (self.autoPlay, show.controls.startDelay, config.browser)
                Task { await autoPlay.press(start, after: delay, browser: browser) }
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
        guard let url = URL(string: "https://www.joyn.de/serien/\(slug)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(JoynCatalog.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return JoynCatalog.matches(of: #"<meta property="og:image" content="([^"]*)""#,
                                   in: String(decoding: data, as: UTF8.self)).first.map(YouTube.decodeEntities)
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

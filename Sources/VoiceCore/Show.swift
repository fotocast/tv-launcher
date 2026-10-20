import Foundation

/// Eine Show, deren Folgen auf dem Mac mini gestartet werden können.
public struct Show: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Serie auf joyn.de – Folgen werden automatisch gelesen. `id` ist der Serien-Slug.
        case joyn
        /// Eigene Show mit selbst eingetragenen Links
        case custom
        /// YouTube-Kanal – die neuesten Videos werden automatisch gelesen. `id` = "youtube-<Kanal-ID>".
        case youtube
        /// Gemerkte Joyn-Filme (eine Sammlung mit der ID `Show.moviesID`, Filme stehen in `links`)
        case movies
        /// Netflix: Serie (`source` = Titelseite, Folgen werden gelesen) oder Sammlung einzelner Titel (`links`)
        case netflix
        /// Prime Video: Serie (`source` = Detailseite einer Staffel) oder Sammlung einzelner Titel (`links`)
        case prime
        /// Disney+: nur Sammlung einzelner Titel (`links`) – Disney+ zeigt ohne Anmeldung keine Inhalte
        case disney

        /// Streamingdienst mit Anmeldung (Netflix, Prime Video, Disney+)
        public var isStreaming: Bool { self == .netflix || self == .prime || self == .disney }
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// Nur bei eigenen Shows: die Folgen/Links
    public var links: [ShowLink]
    public var controls: ShowControls
    /// Nur bei YouTube: Kanal-ID ("UC…"). Beim Anlegen darf hier auch eine Kanal-Adresse oder @Name stehen,
    /// der Server ermittelt daraus die Kanal-ID.
    public var channel: String?
    /// Bild der Show (YouTube: Kanalbild)
    public var image: String?
    /// Ordner, in dem die Show steht (`nil` = kein Ordner). Ordner gibt es nur über ihre Shows.
    public var folder: String?
    /// Netflix/Prime Video: Adresse der Titel- bzw. Staffelseite, aus der die Folgen gelesen werden
    public var source: String?

    /// Streaming-Sammlung mit einzeln gemerkten Titeln (statt automatisch gelesener Folgen)
    public var isLinkCollection: Bool {
        kind == .custom || kind == .movies || (kind.isStreaming && source == nil)
    }

    public init(id: String, name: String, kind: Kind, links: [ShowLink] = [], controls: ShowControls,
                channel: String? = nil, image: String? = nil, folder: String? = nil, source: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.links = links
        self.controls = controls
        self.channel = channel
        self.image = image
        self.folder = folder
        self.source = source
    }

    public static func joyn(series: String, name: String) -> Show {
        Show(id: series, name: name, kind: .joyn, controls: .joynDefault)
    }

    public static func custom(name: String) -> Show {
        Show(id: "custom-" + UUID().uuidString.lowercased().prefix(8), name: name, kind: .custom,
             controls: .customDefault)
    }

    /// YouTube-Kanal aus einer Adresse (https://www.youtube.com/@name, /channel/UC…) oder "@name"
    public static func youtube(channel: String, name: String) -> Show {
        Show(id: "youtube-" + UUID().uuidString.lowercased().prefix(8), name: name, kind: .youtube,
             controls: .youtubeDefault, channel: channel)
    }

    /// Sammlung der gemerkten Joyn-Filme
    public static let moviesID = "joyn-filme"
    public static let movies = Show(id: moviesID, name: "Filme", kind: .movies, controls: .joynDefault)

    /// Sammlung einzeln gestarteter YouTube-Videos (eigene Show mit YouTube-Tasten)
    public static let youtubeVideosID = "custom-youtube-videos"
    public static let youtubeVideos = Show(id: youtubeVideosID, name: "YouTube-Videos", kind: .custom,
                                           controls: .youtubeDefault)

    /// Sammlungen einzeln gemerkter Titel der Streamingdienste
    public static func streamCollection(_ kind: Kind) -> Show {
        switch kind {
        case .netflix: return Show(id: "stream-netflix", name: "Netflix", kind: .netflix, controls: .netflixDefault)
        case .prime: return Show(id: "stream-prime", name: "Prime Video", kind: .prime, controls: .primeDefault)
        default: return Show(id: "stream-disney", name: "Disney+", kind: .disney, controls: .disneyDefault)
        }
    }

    /// Netflix-Serie bzw. -Film mit automatisch gelesenen Folgen
    public static func netflix(titleID: String, name: String) -> Show {
        var show = Show(id: "netflix-\(titleID)", name: name, kind: .netflix, controls: .netflixDefault)
        show.source = "https://www.netflix.com/title/\(titleID)"
        return show
    }

    /// Prime-Video-Serie (eine Staffelseite) mit automatisch gelesenen Folgen
    public static func prime(pageID: String, name: String) -> Show {
        var show = Show(id: "prime-\(pageID.lowercased())", name: name, kind: .prime, controls: .primeDefault)
        show.source = "https://www.primevideo.com/detail/\(pageID)"
        return show
    }

    /// Netflix-Titel-ID aus /title/<id> oder /watch/<id>
    public static func netflixID(in text: String) -> String? {
        guard let url = URL(string: text.contains("://") ? text : "https://\(text)"),
              let host = url.host?.lowercased(), host.hasSuffix("netflix.com") else { return nil }
        // Im Netflix-Katalog öffnen sich Titel als Fenster: /browse?jbv=<id>
        if let jbv = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "jbv" })?.value, !jbv.isEmpty, jbv.allSatisfy(\.isNumber) {
            return jbv
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(where: { $0 == "title" || $0 == "watch" }), index + 1 < parts.count,
              parts[index + 1].allSatisfy(\.isNumber) else { return nil }
        return parts[index + 1]
    }

    /// Prime-Video-Kennung aus /detail/<ID> (primevideo.com) oder /dp/<ASIN> bzw. /gp/video/detail/<ASIN> (amazon.de)
    public static func primeID(in text: String) -> String? {
        guard let url = URL(string: text.contains("://") ? text : "https://\(text)"),
              let host = url.host?.lowercased(), host.contains("primevideo.") || host.contains("amazon.") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(where: { $0 == "detail" || $0 == "dp" }), index + 1 < parts.count else {
            return nil
        }
        let id = parts[index + 1]
        return id.range(of: "^[A-Z0-9]{10,}$", options: .regularExpression) != nil ? id : nil
    }

    /// Disney+-Adresse (jede Seite auf disneyplus.com)
    public static func isDisneyLink(_ text: String) -> Bool {
        guard let url = URL(string: text.contains("://") ? text : "https://\(text)"),
              let host = url.host?.lowercased() else { return false }
        return host.hasSuffix("disneyplus.com") || host.hasSuffix("disney.plus")
    }

    /// Video-ID aus einem YouTube-Link (watch?v=, youtu.be/, /shorts/, /live/, /embed/) oder eine nackte ID
    public static func youtubeVideoID(in text: String) -> String? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let idPattern = "^[A-Za-z0-9_-]{11}$"
        if input.range(of: idPattern, options: .regularExpression) != nil { return input }
        guard let url = URL(string: input.contains("://") ? input : "https://\(input)"),
              let host = url.host?.lowercased(),
              host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be") || host.hasSuffix("youtube-nocookie.com")
        else { return nil }
        var candidate: String?
        if host.hasSuffix("youtu.be") {
            candidate = url.path.split(separator: "/").first.map(String.init)
        } else if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value {
            candidate = v
        } else {
            let parts = url.path.split(separator: "/").map(String.init)
            if let index = parts.firstIndex(where: { ["shorts", "live", "embed", "v"].contains($0) }),
               index + 1 < parts.count {
                candidate = parts[index + 1]
            }
        }
        guard let candidate, candidate.range(of: idPattern, options: .regularExpression) != nil else { return nil }
        return candidate
    }

    /// Die ursprüngliche Show
    public static let theVoice = Show.joyn(series: Episode.series, name: "The Voice of Germany")

    /// Seite der Serie auf joyn.de
    public var joynURL: URL? {
        kind == .joyn ? URL(string: "https://www.joyn.de/serien/\(id)") : nil
    }

    /// Kanalseite auf YouTube
    public var youtubeURL: URL? {
        guard kind == .youtube, let channel else { return nil }
        return URL(string: "https://www.youtube.com/channel/\(channel)")
    }

    /// Erkennt einen Joyn-Film in einer Adresse wie https://www.joyn.de/filme/<slug> (auch /play/filme/<slug>)
    public static func joynMovie(in url: URL) -> String? {
        guard let host = url.host, host.hasSuffix("joyn.de") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "filme"), index + 1 < parts.count else { return nil }
        let slug = parts[index + 1]
        return slug.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil ? slug : nil
    }

    /// Abspiel-Adresse eines Joyn-Films
    public static func joynMoviePlayURL(_ slug: String) -> String {
        "https://www.joyn.de/play/filme/\(slug)"
    }

    /// Erkennt einen YouTube-Kanal in einer Adresse: /@name, /channel/UC…, /c/name, /user/name.
    /// Gibt die Adresse der Kanalseite zurück (ohne Unterseiten wie /videos).
    public static func youtubeChannel(in url: URL) -> String? {
        guard let host = url.host?.lowercased(), host.hasSuffix("youtube.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return nil }
        if first.hasPrefix("@") { return "https://www.youtube.com/\(first)" }
        if ["channel", "c", "user"].contains(first), parts.count > 1 {
            return "https://www.youtube.com/\(first)/\(parts[1])"
        }
        return nil
    }

    /// Folgen einer eigenen Show bzw. Filme der Film-Sammlung (aus den Links)
    public var customEpisodes: [Episode] {
        links.enumerated().map {
            Episode(link: $0.element, number: $0.offset + 1, show: id,
                    subtitle: kind == .movies ? "Joyn-Film" : $0.element.note ?? (kind.isStreaming ? name : nil))
        }
    }

    /// Erkennt den Serien-Slug in einer Joyn-Adresse wie https://www.joyn.de/serien/<slug>/...
    public static func joynSeries(in url: URL) -> String? {
        guard let host = url.host, host.hasSuffix("joyn.de") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        // auch /play/serien/<slug>/...
        guard let index = parts.firstIndex(of: "serien"), index + 1 < parts.count,
              !parts.contains("bts") else { return nil }
        let slug = parts[index + 1]
        return slug.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil ? slug : nil
    }
}

/// Ein eigener Link (eine "Folge" einer eigenen Show)
public struct ShowLink: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    /// Vorschaubild (Filme: Titelbild von Joyn, YouTube-Videos: Vorschaubild)
    public var image: String?
    /// Zusatz unter dem Titel (YouTube-Videos: Kanalname)
    public var note: String?

    public init(id: String = UUID().uuidString.lowercased(), title: String, url: String, image: String? = nil,
                note: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.image = image
        self.note = note
    }
}

/// Was der Server für eine Aktion am Mac mini auslöst.
public struct KeyBinding: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case none
        /// Taste mit Modifiern
        case key
        /// Doppelklick auf die Bildmitte
        case doubleClick
    }

    public var kind: Kind
    /// macOS-Tastencode
    public var keyCode: UInt16?
    /// Modifier als CGEventFlags/NSEvent.ModifierFlags-Rohwert (⌘ ⌥ ⇧ ⌃)
    public var modifiers: UInt64?
    /// Anzeige, z. B. "Leertaste" oder "⌘→"
    public var label: String

    public init(kind: Kind, keyCode: UInt16? = nil, modifiers: UInt64? = nil, label: String) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    public static let none = KeyBinding(kind: .none, label: "Keine")
    public static let doubleClick = KeyBinding(kind: .doubleClick, label: "Doppelklick Bildmitte")
    public static func key(_ code: UInt16, _ label: String, modifiers: UInt64 = 0) -> KeyBinding {
        KeyBinding(kind: .key, keyCode: code, modifiers: modifiers, label: label)
    }

    public static let space = key(49, "Leertaste")
    /// YouTube: Untertitel an/aus
    public static let c = key(8, "C")
    /// Browser-Tab schließen (⌘W) – gilt für jede Show
    public static let closeTab = key(13, "⌘W", modifiers: 1 << 20)
    public static let left = key(123, "←")
    public static let right = key(124, "→")
}

/// Tastenbelegung einer Show
public struct ShowControls: Codable, Hashable, Sendable {
    public var playPause: KeyBinding
    public var back: KeyBinding
    public var forward: KeyBinding
    public var fullscreen: KeyBinding
    /// Wird nach dem Öffnen einer Folge gedrückt (z. B. Leertaste, damit Joyn startet)
    public var start: KeyBinding
    /// Sekunden bis `start` gedrückt wird
    public var startDelay: Double
    /// Untertitel an/aus (fehlt in älteren Daten → keine Taste)
    public var subtitles: KeyBinding
    /// Lautstärke im Player – nur nötig, wenn der Mac die Lautstärke nicht selbst regeln kann (Ton über HDMI)
    public var volumeUp: KeyBinding
    public var volumeDown: KeyBinding
    public var mute: KeyBinding
    /// Eigene Knöpfe für die Fernbedienung (z. B. „Nächstes Video“ = ⇧N)
    public var customButtons: [CustomButton]

    public init(playPause: KeyBinding, back: KeyBinding, forward: KeyBinding, fullscreen: KeyBinding,
                start: KeyBinding, startDelay: Double, subtitles: KeyBinding = .none,
                volumeUp: KeyBinding = .none, volumeDown: KeyBinding = .none, mute: KeyBinding = .none,
                customButtons: [CustomButton] = []) {
        self.playPause = playPause
        self.back = back
        self.forward = forward
        self.fullscreen = fullscreen
        self.start = start
        self.startDelay = startDelay
        self.subtitles = subtitles
        self.volumeUp = volumeUp
        self.volumeDown = volumeDown
        self.mute = mute
        self.customButtons = customButtons
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playPause = try c.decode(KeyBinding.self, forKey: .playPause)
        back = try c.decode(KeyBinding.self, forKey: .back)
        forward = try c.decode(KeyBinding.self, forKey: .forward)
        fullscreen = try c.decode(KeyBinding.self, forKey: .fullscreen)
        start = try c.decode(KeyBinding.self, forKey: .start)
        startDelay = try c.decode(Double.self, forKey: .startDelay)
        subtitles = try c.decodeIfPresent(KeyBinding.self, forKey: .subtitles) ?? .none
        volumeUp = try c.decodeIfPresent(KeyBinding.self, forKey: .volumeUp) ?? .none
        volumeDown = try c.decodeIfPresent(KeyBinding.self, forKey: .volumeDown) ?? .none
        mute = try c.decodeIfPresent(KeyBinding.self, forKey: .mute) ?? .none
        customButtons = try c.decodeIfPresent([CustomButton].self, forKey: .customButtons) ?? []
    }

    /// Joyn-Player: Leertaste, Pfeiltasten, Vollbild per Doppelklick, Start per Leertaste.
    /// Untertitel lassen sich bei Joyn nicht per Taste schalten (nur im Player-Menü).
    public static let joynDefault = ShowControls(playPause: .space, back: .left, forward: .right,
                                                 fullscreen: .doubleClick, start: .space, startDelay: 10)
    /// YouTube: K = Pause/Weiter, J/L = 10 s zurück/vor, F = Vollbild, C = Untertitel, ↑/↓/M = Lautstärke; K nach 5 s startet
    /// das Video, weil Firefox automatisches Abspielen mit Ton blockiert
    public static let youtubeDefault = ShowControls(playPause: .key(40, "K"), back: .key(38, "J"),
                                                    forward: .key(37, "L"), fullscreen: .key(3, "F"),
                                                    start: .key(40, "K"), startDelay: 5, subtitles: .c,
                                                    volumeUp: .key(126, "↑"), volumeDown: .key(125, "↓"),
                                                    mute: .key(46, "M"))
    /// Netflix: Leertaste, ←/→ 10 s, F Vollbild, ↑/↓/M Lautstärke; Leertaste nach 8 s, weil Firefox Autoplay mit Ton blockiert
    public static let netflixDefault = ShowControls(playPause: .space, back: .left, forward: .right,
                                                    fullscreen: .key(3, "F"), start: .space, startDelay: 8,
                                                    volumeUp: .key(126, "↑"), volumeDown: .key(125, "↓"),
                                                    mute: .key(46, "M"))
    /// Prime Video: wie Netflix
    public static let primeDefault = netflixDefault
    /// Disney+: wie Netflix
    public static let disneyDefault = netflixDefault

    /// Eigene Shows: Leertaste, Pfeiltasten, F für Vollbild, nichts beim Start
    public static let customDefault = ShowControls(playPause: .space, back: .left, forward: .right,
                                                   fullscreen: .key(3, "F"), start: .none, startDelay: 5)

    public func binding(for action: PlayerAction) -> KeyBinding {
        switch action {
        case .playPause: return playPause
        case .back: return back
        case .forward: return forward
        case .fullscreen: return fullscreen
        case .subtitles: return subtitles
        case .closeTab: return .closeTab
        case .custom: return .none   // eigene Knöpfe: siehe `customButtons`
        }
    }
}

// MARK: - Eigene Knöpfe

/// Eigener Knopf in der Fernbedienung: Name, Symbol und was am Mac gedrückt wird.
public struct CustomButton: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    /// Kennung aus `ButtonIcon.all`
    public var icon: String
    public var binding: KeyBinding

    public init(id: String = UUID().uuidString.lowercased(), title: String, icon: String, binding: KeyBinding) {
        self.id = id
        self.title = title
        self.icon = icon
        self.binding = binding
    }

    private static let shift: UInt64 = 1 << 17

    /// Vorschläge passend zur Art der Show
    public static func suggestions(for kind: Show.Kind) -> [CustomButton] {
        switch kind {
        case .youtube:
            return [
                CustomButton(title: "Nächstes Video", icon: "next", binding: .key(45, "⇧N", modifiers: shift)),
                CustomButton(title: "Vorheriges Video", icon: "previous", binding: .key(35, "⇧P", modifiers: shift)),
                CustomButton(title: "Schneller", icon: "faster", binding: .key(47, "⇧.", modifiers: shift)),
                CustomButton(title: "Langsamer", icon: "slower", binding: .key(43, "⇧,", modifiers: shift)),
                CustomButton(title: "Zum Anfang", icon: "restart", binding: .key(29, "0")),
                CustomButton(title: "Kinomodus", icon: "theater", binding: .key(17, "T")),
                CustomButton(title: "Miniplayer", icon: "pip", binding: .key(34, "I")),
            ]
        case .joyn, .movies:
            return [
                CustomButton(title: "Vollbild verlassen", icon: "close", binding: .key(53, "esc")),
                CustomButton(title: "Bestätigen", icon: "ok", binding: .key(36, "⏎")),
            ]
        case .custom:
            return [
                CustomButton(title: "Bestätigen", icon: "ok", binding: .key(36, "⏎")),
                CustomButton(title: "Zurück", icon: "back", binding: .key(53, "esc")),
            ]
        case .netflix:
            return [
                CustomButton(title: "Intro überspringen", icon: "skip", binding: .key(1, "S")),
                CustomButton(title: "Vollbild verlassen", icon: "close", binding: .key(53, "esc")),
            ]
        case .prime, .disney:
            return [
                CustomButton(title: "Vollbild verlassen", icon: "close", binding: .key(53, "esc")),
                CustomButton(title: "Bestätigen", icon: "ok", binding: .key(36, "⏎")),
            ]
        }
    }
}

/// Symbole für eigene Knöpfe: SF Symbol (Mac-App) und Emoji (Web-App)
public struct ButtonIcon: Sendable, Hashable, Identifiable {
    public let id: String
    public let symbol: String
    public let emoji: String

    public static let all: [ButtonIcon] = [
        .init(id: "star", symbol: "star.fill", emoji: "⭐"),
        .init(id: "heart", symbol: "heart.fill", emoji: "❤️"),
        .init(id: "next", symbol: "forward.end.fill", emoji: "⏭️"),
        .init(id: "previous", symbol: "backward.end.fill", emoji: "⏮️"),
        .init(id: "skip", symbol: "goforward", emoji: "⏩"),
        .init(id: "rewind", symbol: "gobackward", emoji: "⏪"),
        .init(id: "faster", symbol: "hare.fill", emoji: "🐇"),
        .init(id: "slower", symbol: "tortoise.fill", emoji: "🐢"),
        .init(id: "restart", symbol: "arrow.counterclockwise", emoji: "🔄"),
        .init(id: "play", symbol: "play.fill", emoji: "▶️"),
        .init(id: "pause", symbol: "pause.fill", emoji: "⏸️"),
        .init(id: "stop", symbol: "stop.fill", emoji: "⏹️"),
        .init(id: "repeat", symbol: "repeat", emoji: "🔁"),
        .init(id: "shuffle", symbol: "shuffle", emoji: "🔀"),
        .init(id: "theater", symbol: "rectangle.inset.filled", emoji: "🎬"),
        .init(id: "pip", symbol: "pip.fill", emoji: "🖼️"),
        .init(id: "captions", symbol: "captions.bubble.fill", emoji: "💬"),
        .init(id: "audio", symbol: "speaker.wave.2.fill", emoji: "🔊"),
        .init(id: "info", symbol: "info.circle.fill", emoji: "ℹ️"),
        .init(id: "menu", symbol: "list.bullet", emoji: "📋"),
        .init(id: "settings", symbol: "gearshape.fill", emoji: "⚙️"),
        .init(id: "home", symbol: "house.fill", emoji: "🏠"),
        .init(id: "back", symbol: "arrow.uturn.backward", emoji: "↩️"),
        .init(id: "ok", symbol: "checkmark.circle.fill", emoji: "✅"),
        .init(id: "close", symbol: "xmark.circle.fill", emoji: "❌"),
        .init(id: "bolt", symbol: "bolt.fill", emoji: "⚡"),
        .init(id: "flag", symbol: "flag.fill", emoji: "🚩"),
        .init(id: "bookmark", symbol: "bookmark.fill", emoji: "🔖"),
        .init(id: "tv", symbol: "tv.fill", emoji: "📺"),
        .init(id: "game", symbol: "gamecontroller.fill", emoji: "🎮"),
    ]

    public static func named(_ id: String) -> ButtonIcon {
        all.first { $0.id == id } ?? all[0]
    }
}

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

    public init(id: String, name: String, kind: Kind, links: [ShowLink] = [], controls: ShowControls,
                channel: String? = nil, image: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.links = links
        self.controls = controls
        self.channel = channel
        self.image = image
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
                    subtitle: kind == .movies ? "Joyn-Film" : $0.element.note)
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

    public init(playPause: KeyBinding, back: KeyBinding, forward: KeyBinding, fullscreen: KeyBinding,
                start: KeyBinding, startDelay: Double) {
        self.playPause = playPause
        self.back = back
        self.forward = forward
        self.fullscreen = fullscreen
        self.start = start
        self.startDelay = startDelay
    }

    /// Joyn-Player: Leertaste, Pfeiltasten, Vollbild per Doppelklick, Start per Leertaste
    public static let joynDefault = ShowControls(playPause: .space, back: .left, forward: .right,
                                                 fullscreen: .doubleClick, start: .space, startDelay: 10)
    /// YouTube: K = Pause/Weiter, J/L = 10 s zurück/vor, F = Vollbild; K nach 5 s startet das Video,
    /// weil Firefox automatisches Abspielen mit Ton blockiert
    public static let youtubeDefault = ShowControls(playPause: .key(40, "K"), back: .key(38, "J"),
                                                    forward: .key(37, "L"), fullscreen: .key(3, "F"),
                                                    start: .key(40, "K"), startDelay: 5)
    /// Eigene Shows: Leertaste, Pfeiltasten, F für Vollbild, nichts beim Start
    public static let customDefault = ShowControls(playPause: .space, back: .left, forward: .right,
                                                   fullscreen: .key(3, "F"), start: .none, startDelay: 5)

    public func binding(for action: PlayerAction) -> KeyBinding {
        switch action {
        case .playPause: return playPause
        case .back: return back
        case .forward: return forward
        case .fullscreen: return fullscreen
        }
    }
}

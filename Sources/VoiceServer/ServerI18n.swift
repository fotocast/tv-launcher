import Foundation

/// Meldungen des Servers auf Englisch, wenn App oder Web-App das per `Accept-Language: en` wünschen.
/// Übersetzt nur die Felder "message" und "error" einer JSON-Antwort (Inhalte wie Titel bleiben).
enum ServerI18n {
    static func wantsEnglish(_ request: HTTPRequest) -> Bool {
        (request.headers["accept-language"] ?? "").lowercased().hasPrefix("en")
    }

    static func translate(_ response: HTTPResponse) -> HTTPResponse {
        guard response.contentType.hasPrefix("application/json"),
              var json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else { return response }
        var changed = false
        for key in ["message", "error"] {
            if let text = json[key] as? String {
                let english = english(text)
                if english != text {
                    json[key] = english
                    changed = true
                }
            }
        }
        guard changed, let body = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
            return response
        }
        var translated = response
        translated.body = body
        return translated
    }

    /// Feste Wendungen und Muster (der Reihe nach angewendet)
    private static let patterns: [(String, String)] = [
        // Abspielen & Steuern
        (#"^(.+) läuft auf dem Mac mini$"#, "$1 is playing on the TV Mac"),
        (#"^„(.+)“ zu YouTube-Videos hinzugefügt$"#, "“$1” added to YouTube videos"),
        (#"^„(.+)“ zu Filmen hinzugefügt$"#, "“$1” added to movies"),
        (#"^Für „(.+)“ ist bei (.+) keine Taste festgelegt\.$"#, "No key is set for “$1” in $2."),
        (#"^(\d+) Eingaben$"#, "$1 inputs"),
        (#"^Pause/Weiter"#, "Play/Pause"),
        (#"^Zurückspulen"#, "Back"),
        (#"^Vorspulen"#, "Forward"),
        (#"^Vollbild"#, "Fullscreen"),
        (#"^Untertitel"#, "Subtitles"),
        (#"^Tab schließen"#, "Close tab"),
        (#"\(Leertaste\)"#, "(Space)"),
        (#"\(Doppelklick Bildmitte\)"#, "(double-click center)"),
        (#"^Server startet neu …$"#, "Server is restarting …"),
        (#"^Lautstärke im Player \((.+)\)$"#, "Volume in the player ($1)"),
        (#"^Der Ton läuft über HDMI – .*und (.+) hat keine Lautstärke-Taste\..*$"#,
         "Sound goes over HDMI – the TV Mac can't change the volume, and $1 has no volume key. Please use the TV's remote."),
        (#"^VoiceServer fehlt am Mac mini die Berechtigung „Bedienungshilfen“.*$"#,
         "VoiceServer on the TV Mac is missing the Accessibility permission (System Settings > Privacy & Security)."),
        (#"^VoiceServer fehlt am Mac mini die Berechtigung „Bildschirm- und Systemaudioaufnahme“.*$"#,
         "VoiceServer on the TV Mac is missing the Screen Recording permission (System Settings > Privacy & Security)."),
        (#"^Browser konnte nicht geöffnet werden: "#, "Could not open the browser: "),
        (#"^Bildschirmfoto fehlgeschlagen: "#, "Screenshot failed: "),
        (#"^open endete mit Status (\d+)$"#, "open exited with status $1"),
        (#"^Lautstärke nicht lesbar$"#, "Could not read the volume"),
        // Shows
        (#"^Die Show braucht einen Namen\.$"#, "The show needs a name."),
        (#"^Das Preset braucht einen Namen\.$"#, "The preset needs a name."),
        (#"^„(.+)“ ist eine eingebaute Vorlage – bitte einen anderen Namen wählen\.$"#,
         "“$1” is a built-in preset – please choose another name."),
        (#"^„(.+)“ ist schon vorhanden\.$"#, "“$1” already exists."),
        (#"^Dieser Kanal ist schon als „(.+)“ hinzugefügt\.$"#, "This channel was already added as “$1”."),
        (#"^Die Serie „(.+)“ wurde auf joyn\.de nicht gefunden\.$"#, "The series “$1” was not found on joyn.de."),
        (#"^Keine Joyn-Serie erkannt\..*$"#, "No Joyn series recognized. Expected a link like joyn.de/serien/…"),
        (#"^Bitte eine Kanal-Adresse oder @Name eingeben\.$"#, "Please enter a channel link or @name."),
        (#"^Für einen YouTube-Kanal fehlt die Kanal-Adresse\.$"#, "The channel link is missing."),
        (#"^Kein YouTube-Kanal gefunden für „(.+)“\..*$"#,
         "No YouTube channel found for “$1”. Please use the channel page link (e.g. https://www.youtube.com/@name)."),
        (#"^Auf dem YouTube-Kanal wurden keine öffentlichen Videos gefunden\.$"#, "No public videos found on this channel."),
        (#"^Ungültiger Link: „(.+)“ \(muss mit http:// oder https:// beginnen\)\.$"#,
         "Invalid link: “$1” (must start with http:// or https://)."),
        (#"^Ungültige Joyn-Serie „(.+)“\.$"#, "Invalid Joyn series “$1”."),
        (#"^Ungültige Show-ID\.$"#, "Invalid show ID."),
        (#"^Filme bitte über /api/movies hinzufügen\.$"#, "Please add movies via /api/movies."),
        // Inhalte
        (#"^Kein YouTube-Video erkannt: „(.+)“$"#, "No YouTube video recognized: “$1”"),
        (#"^Kein Joyn-Film erkannt: „(.+)“$"#, "No Joyn movie recognized: “$1”"),
        (#"^Film „(.+)“ auf joyn\.de nicht gefunden\.$"#, "Movie “$1” not found on joyn.de."),
        (#"^Folgen konnten nicht von joyn\.de geladen werden: "#, "Could not load episodes from joyn.de: "),
        (#"^Auf joyn\.de wurden keine Folgen gefunden\.$"#, "No episodes found on joyn.de."),
        (#"^joyn\.de antwortet mit Status (\d+) \((.+)\)\.$"#, "joyn.de answered with status $1 ($2)."),
        (#"^YouTube-Suche fehlgeschlagen: "#, "YouTube search failed: "),
        (#"^Suchbegriff fehlt$"#, "Search term missing"),
        (#"^Keine gültige TV-Launcher-Sicherung$"#, "Not a valid TV Launcher backup"),
        (#"^Log nicht gefunden: "#, "Log not found: "),
        (#"^Unbekannte Show$"#, "Unknown show"),
        (#"^Unbekannte Folge$"#, "Unknown episode"),
        (#"^Unbekannte Aktion „(.+)“$"#, "Unknown action “$1”"),
        (#"^(Video|Film) nicht gefunden$"#, "Not found"),
        (#"^Kanal fehlt$"#, "Channel missing"),
        (#"^Ungültige Adresse$"#, "Invalid address"),
        (#"^Ungültige Anfrage$"#, "Invalid request"),
        (#"^Nicht gefunden$"#, "Not found"),
        (#"^Nicht erlaubt$"#, "Not allowed"),
        (#"^Erwartet wird "#, "Expected "),
        (#" mit einem von: "#, " with one of: "),
    ]

    private static let compiled: [(NSRegularExpression, String)] = patterns.compactMap { pattern, template in
        (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
    }

    static func english(_ text: String) -> String {
        var result = text
        for (regex, template) in compiled {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }
}

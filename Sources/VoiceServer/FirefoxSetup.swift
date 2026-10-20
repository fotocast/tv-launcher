import Foundation

/// Richtet das Firefox-Standardprofil für den Konsolenbetrieb ein (user.js, wird bei jedem Firefox-Start gelesen):
/// keine alten Tabs beim Start, keine „Sitzung wiederherstellen“-Seite, keine Rückfrage beim Beenden.
/// Nur der markierte Block gehört dem Server – eigene Zeilen in user.js bleiben erhalten.
enum FirefoxSetup {
    private static let begin = "// >>> TV Launcher (automatisch, nicht bearbeiten)"
    private static let end = "// <<< TV Launcher"
    private static let prefs = [
        "browser.startup.page": "0",
        "browser.sessionstore.resume_from_crash": "false",
        "browser.tabs.warnOnClose": "false",
        "browser.warnOnQuit": "false",
        "browser.warnOnQuitShortcut": "false",
        "browser.aboutwelcome.enabled": "false",
    ]

    static func apply() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox")
        guard let profile = defaultProfile(in: base) else {
            serverLog("Firefox-Profil nicht gefunden – user.js nicht angelegt.")
            return
        }
        let file = profile.appendingPathComponent("user.js")
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<stop.upperBound)
        }
        let block = ([begin] + prefs.sorted { $0.key < $1.key }.map { "user_pref(\"\($0.key)\", \($0.value));" } + [end])
            .joined(separator: "\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = (text.isEmpty ? "" : text + "\n\n") + block + "\n"
        do {
            try text.write(to: file, atomically: true, encoding: .utf8)
            serverLog("Firefox eingerichtet: \(file.path)")
        } catch {
            serverLog("Firefox-Einstellungen nicht geschrieben: \(error.localizedDescription)")
        }
    }

    /// Profil aus profiles.ini: zuerst der [Install…]-Eintrag (das Profil, das Firefox wirklich nutzt),
    /// sonst das Profil mit Default=1.
    private static func defaultProfile(in base: URL) -> URL? {
        guard let ini = try? String(contentsOf: base.appendingPathComponent("profiles.ini"), encoding: .utf8) else {
            return nil
        }
        var installDefault: String?
        var markedDefault: String?
        var section = ""
        var path: String?
        var isRelative = true
        func finishProfile(isDefault: Bool) {
            if isDefault, let path { markedDefault = isRelative ? path : "/" + path }
        }
        var currentIsDefault = false
        for raw in ini.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if section.hasPrefix("[Profile") { finishProfile(isDefault: currentIsDefault) }
                section = line
                path = nil
                isRelative = true
                currentIsDefault = false
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if section.hasPrefix("[Install"), parts[0] == "Default" { installDefault = parts[1] }
            if section.hasPrefix("[Profile") {
                switch parts[0] {
                case "Path": path = parts[1]
                case "IsRelative": isRelative = parts[1] == "1"
                case "Default": currentIsDefault = parts[1] == "1"
                default: break
                }
            }
        }
        if section.hasPrefix("[Profile") { finishProfile(isDefault: currentIsDefault) }
        guard let chosen = installDefault ?? markedDefault else { return nil }
        return chosen.hasPrefix("/") ? URL(fileURLWithPath: chosen) : base.appendingPathComponent(chosen)
    }
}

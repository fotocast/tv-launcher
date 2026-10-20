import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VoiceCore

// MARK: - Sprache

/// Sprache der App: setzt `AppleLanguages` für diese App (wirkt nach einem Neustart).
enum AppLanguage {
    static func apply(_ language: String) {
        if language == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
    }

    /// App beenden und sofort wieder öffnen
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"\(Bundle.main.bundlePath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Wiedergabe (Einstellungen auf dem Server)

struct PlaybackSettingsView: View {
    @EnvironmentObject private var model: EpisodeModel
    @State private var draft = ServerSettings()
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    private static let seasonChoices = [2, 3, 5, 10, 0]
    private static let refreshChoices = [15, 30, 60, 180, 720]
    private static let sleepChoices = [15, 30, 45, 60, 90, 120]

    var body: some View {
        Form {
            Section {
                Toggle("Automatisch Vollbild", isOn: $draft.autoFullscreen)
                if draft.autoFullscreen {
                    Stepper(value: $draft.fullscreenDelay, in: 0...30, step: 1) {
                        Text("\(Int(draft.fullscreenDelay)) Sekunden nach der Start-Taste")
                    }
                }
                Toggle("Lautstärke beim Start festlegen", isOn: Binding(
                    get: { draft.startVolume != nil },
                    set: { draft.startVolume = $0 ? (model.volume?.volume ?? 50) : nil }))
                if let volume = draft.startVolume {
                    Slider(value: Binding(get: { Double(volume) }, set: { draft.startVolume = Int($0) }),
                           in: 0...100, step: 5) {
                        Text("Lautstärke")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    Text("\(volume) %").font(.caption).foregroundStyle(.secondary)
                }
                if model.serverStatus != nil, model.serverStatus?.volume == nil {
                    Label("Der Ton läuft über HDMI – dort kann der Mac die Lautstärke nicht festlegen. Lauter/Leiser in der Fernbedienung nutzt dann die Tasten des Players (YouTube: ↑/↓/M).",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Beim Start eines Videos")
            } footer: {
                Text("Vollbild nutzt die Taste der Show (Joyn: Doppelklick auf die Bildmitte, YouTube: F).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Joyn-Staffeln", selection: $draft.joynSeasons) {
                    ForEach(Self.seasonChoices, id: \.self) { count in
                        Text(count == 0 ? String(localized: "Alle") : String(localized: "Die neuesten \(count)")).tag(count)
                    }
                }
                Picker("YouTube aktualisieren", selection: $draft.youtubeRefreshMinutes) {
                    ForEach(Self.refreshChoices, id: \.self) { minutes in
                        Text(minutes < 60 ? String(localized: "alle \(minutes) Minuten")
                             : String(localized: "alle \(minutes / 60) Stunden")).tag(minutes)
                    }
                }
            } header: {
                Text("Inhalte")
            } footer: {
                Text("Mehr Staffeln: Beim ersten Laden sucht der Server einmalig in der Joyn-Sitemap, das dauert etwas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let end = model.serverStatus?.sleepAt {
                    HStack {
                        Label("Läuft bis \(end.formatted(date: .omitted, time: .shortened))", systemImage: "moon.zzz.fill")
                        Spacer()
                        Button("Ausschalten") { Task { await model.setSleepTimer(minutes: 0) } }
                    }
                }
                HStack {
                    ForEach(Self.sleepChoices, id: \.self) { minutes in
                        Button("\(minutes) Min.") { Task { await model.setSleepTimer(minutes: minutes) } }
                    }
                }
            } header: {
                Text("Sleep-Timer")
            } footer: {
                Text("Nach Ablauf pausiert der Mac mini das Video und schaltet das Display aus. Auch in der Fernbedienung.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(!loaded)
        .task {
            await model.loadServerInfo()
            if let settings = model.serverSettings { draft = settings }
            loaded = true
        }
        .onChange(of: draft) { value in
            guard loaded, value != model.serverSettings else { return }
            // Kurz warten, damit beim Ziehen des Reglers nicht jede Stufe gesendet wird
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                await model.saveServerSettings(value)
            }
        }
    }
}

// MARK: - Startseite

/// Abschnitte der Startseite, die sich ausblenden lassen
enum HomeSection: String, CaseIterable, Identifiable {
    case continueWatching, newest, series, channels, movies, videos, custom

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .continueWatching: return "Weiterschauen"
        case .newest: return "Neueste Folgen"
        case .series: return "Serien"
        case .channels: return "YouTube-Kanäle"
        case .movies: return "Filme"
        case .videos: return "Zuletzt gestartete YouTube-Videos"
        case .custom: return "Eigene Shows"
        }
    }

    /// Aus UserDefaults: ausgeblendete Abschnitte
    static func hidden(_ raw: String) -> Set<HomeSection> {
        Set(raw.split(separator: "\n").compactMap { HomeSection(rawValue: String($0)) })
    }
}

/// Kachelgröße der Startseite (Mindestbreite einer Kachel)
enum TileSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var minimumWidth: CGFloat {
        switch self {
        case .small: return 180
        case .medium: return 230
        case .large: return 310
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .small: return "Klein"
        case .medium: return "Mittel"
        case .large: return "Groß"
        }
    }
}

struct HomeSettingsView: View {
    @AppStorage(AppSettings.homeHiddenKey) private var hiddenRaw = ""
    @AppStorage(AppSettings.tileSizeKey) private var tileSize = TileSize.medium.rawValue

    var body: some View {
        Form {
            Section {
                ForEach(HomeSection.allCases) { section in
                    Toggle(section.label, isOn: Binding(
                        get: { !HomeSection.hidden(hiddenRaw).contains(section) },
                        set: { visible in
                            var hidden = HomeSection.hidden(hiddenRaw)
                            if visible { hidden.remove(section) } else { hidden.insert(section) }
                            hiddenRaw = HomeSection.allCases.filter(hidden.contains).map(\.rawValue).joined(separator: "\n")
                        }))
                }
            } header: {
                Text("Abschnitte")
            }
            Section {
                Picker("Kachelgröße", selection: $tileSize) {
                    ForEach(TileSize.allCases) { size in
                        Text(size.label).tag(size.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Darstellung")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Fernsteuerung

struct RemoteSettingsView: View {
    @AppStorage(AppSettings.pointerSpeedKey) private var pointerSpeed = AppSettings.defaultPointerSpeed
    @AppStorage(AppSettings.screenshotIntervalKey) private var screenshotInterval = AppSettings.defaultScreenshotInterval
    @AppStorage(AppSettings.invertScrollKey) private var invertScroll = false
    @AppStorage(AppSettings.playbackShortcutsKey) private var shortcuts = true

    var body: some View {
        Form {
            Section {
                Slider(value: $pointerSpeed, in: 0.5...4, step: 0.25) {
                    Text("Zeigertempo")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                Toggle("Scrollrichtung umkehren", isOn: $invertScroll)
            } header: {
                Text("Zeiger steuern")
            } footer: {
                Text("Gilt für „Zeiger steuern“ und „Bildschirm anklicken“.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Bild aktualisieren", selection: $screenshotInterval) {
                    ForEach(AppSettings.screenshotIntervals, id: \.self) { seconds in
                        Text(AppSettings.intervalLabel(seconds)).tag(seconds)
                    }
                }
            } header: {
                Text("Bildschirm anklicken")
            } footer: {
                Text("Nach jedem Klick, Scrollen und Tippen kommt ohnehin ein neues Bild. Kürzere Abstände belasten den Mac mini etwas mehr.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Tastenkürzel im Menü „Wiedergabe“", isOn: $shortcuts)
                if shortcuts {
                    ForEach(PlaybackShortcut.allCases) { shortcut in
                        LabeledContent(shortcut.title) {
                            Text(shortcut.display).font(.body.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Tastenkürzel")
            } footer: {
                Text("Funktionieren, solange die App vorne ist und „Zeiger steuern“ nicht läuft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Tastenkürzel im Menü „Wiedergabe“ der Mac-App
enum PlaybackShortcut: String, CaseIterable, Identifiable {
    case playPause, back, forward, fullscreen, subtitles, closeTab, volumeUp, volumeDown, mute

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .playPause: return "Pause/Weiter"
        case .back: return "10 Sekunden zurück"
        case .forward: return "10 Sekunden vor"
        case .fullscreen: return "Vollbild"
        case .subtitles: return "Untertitel"
        case .closeTab: return "Tab schließen"
        case .volumeUp: return "Lauter"
        case .volumeDown: return "Leiser"
        case .mute: return "Ton aus/an"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .playPause: return "k"
        case .back: return .leftArrow
        case .forward: return .rightArrow
        case .fullscreen: return "f"
        case .subtitles: return "u"
        case .closeTab: return "x"
        case .volumeUp: return .upArrow
        case .volumeDown: return .downArrow
        case .mute: return "0"
        }
    }

    var modifiers: EventModifiers { [.command, .option] }

    var display: String {
        switch self {
        case .back: return "⌥⌘←"
        case .forward: return "⌥⌘→"
        case .volumeUp: return "⌥⌘↑"
        case .volumeDown: return "⌥⌘↓"
        default: return "⌥⌘" + String(key.character).uppercased()
        }
    }

    var action: PlayerAction? {
        switch self {
        case .playPause: return .playPause
        case .back: return .back
        case .forward: return .forward
        case .fullscreen: return .fullscreen
        case .subtitles: return .subtitles
        case .closeTab: return .closeTab
        default: return nil
        }
    }

    var volumeAction: String? {
        switch self {
        case .volumeUp: return "up"
        case .volumeDown: return "down"
        case .mute: return "mute"
        default: return nil
        }
    }
}

/// Menü „Wiedergabe“ mit Tastenkürzeln
struct PlaybackCommands: Commands {
    let model: EpisodeModel
    @AppStorage(AppSettings.playbackShortcutsKey) private var enabled = true

    var body: some Commands {
        CommandMenu("Wiedergabe") {
            ForEach(PlaybackShortcut.allCases) { shortcut in
                let button = Button(shortcut.title) {
                    Task { @MainActor in
                        if let action = shortcut.action {
                            await model.control(action)
                        } else if let volume = shortcut.volumeAction {
                            await model.changeVolume(volume)
                        }
                    }
                }
                if enabled {
                    button.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                } else {
                    button
                }
                if shortcut == .closeTab { Divider() }
            }
        }
    }
}

// MARK: - Mac mini: Status & Wartung

struct MacMiniSettingsView: View {
    @EnvironmentObject private var model: EpisodeModel
    @State private var log = ""
    @State private var isWorking = false
    @State private var confirmRestart = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if let status = model.serverStatus {
                    LabeledContent("Version", value: status.version == TVLauncher.version
                                   ? status.version : "\(status.version) (App: \(TVLauncher.version))")
                    LabeledContent("Rechner", value: status.host)
                    LabeledContent("Browser", value: status.browser)
                    LabeledContent("Alte Tabs schließen") {
                        Text(status.closeOldTabs ? "an" : "aus")
                    }
                    LabeledContent("Läuft seit") {
                        Text(status.startedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let volume = status.volume {
                        LabeledContent("Lautstärke") {
                            Text(status.muted == true ? String(localized: "stumm") : "\(volume) %")
                        }
                    }
                } else {
                    Text(errorMessage ?? String(localized: "Lädt …")).foregroundStyle(.secondary)
                }
            } header: {
                Text("Server")
            }

            Section {
                permission("Bedienungshilfen", ok: model.serverStatus?.accessibility,
                           detail: "Nötig für Play/Pause, Spulen, Vollbild und das automatische Starten.")
                permission("Bildschirmaufnahme", ok: model.serverStatus?.screenRecording,
                           detail: "Nur für „Bildschirm anklicken“.")
            } header: {
                Text("Berechtigungen am Mac mini")
            } footer: {
                Text("Erteilen am Mac mini: Systemeinstellungen → Datenschutz & Sicherheit → Eintrag wählen → „VoiceServer“ einschalten (mit + hinzufügen: ⇧⌘G, ~/TheVoiceServer/VoiceServer).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Status aktualisieren") { Task { await model.loadServerInfo() } }
                    Button("Log laden") { loadLog() }
                    Spacer()
                    if isWorking { ProgressView().controlSize(.small) }
                    Button("Server neu starten …") { confirmRestart = true }
                }
                if !log.isEmpty {
                    ScrollView {
                        Text(log)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Wartung")
            }
        }
        .formStyle(.grouped)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.loadServerInfo() }
        .confirmationDialog("Server neu starten?", isPresented: $confirmRestart) {
            Button("Neu starten") {
                isWorking = true
                Task {
                    do { try await model.restartServer() } catch { errorMessage = error.localizedDescription }
                    isWorking = false
                }
            }
        } message: {
            Text("Der Server ist danach in wenigen Sekunden wieder da. Ein laufendes Video läuft weiter.")
        }
    }

    private func permission(_ title: LocalizedStringKey, ok: Bool?, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : ok == false ? "xmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(ok == true ? .green : ok == false ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ok == true ? "erlaubt" : ok == false ? "fehlt" : "–").foregroundStyle(.secondary)
        }
    }

    private func loadLog() {
        isWorking = true
        errorMessage = nil
        Task {
            do { log = try await model.serverLog() } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }
}

// MARK: - Sicherung

struct BackupSettingsView: View {
    @EnvironmentObject private var model: EpisodeModel
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var pendingRestore: Data?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                Text("Speichert alle Shows (inkl. Links und Filme), eigene Tasten-Presets und die Einstellungen des Servers in einer Datei.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Sicherung exportieren …") { export() }
                    Button("Sicherung einspielen …") { chooseRestore() }
                    Spacer()
                    if isWorking { ProgressView().controlSize(.small) }
                }
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.orange)
                }
            } header: {
                Text("Sicherung")
            } footer: {
                Text("Einstellungen dieser App (Sprache, Startseite, Fernsteuerung) gehören nicht dazu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Sicherung einspielen?", isPresented: Binding(get: { pendingRestore != nil },
                                                           set: { if !$0 { pendingRestore = nil } })) {
            Button("Einspielen", role: .destructive) {
                if let data = pendingRestore { restore(data) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Shows, Presets und Server-Einstellungen werden durch die Sicherung ersetzt – in der App und in der Web-App.")
        }
    }

    private func export() {
        errorMessage = nil
        message = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let data = try await model.backupData()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                let day = Date().formatted(.iso8601.year().month().day())
                panel.nameFieldStringValue = "TV-Launcher-Sicherung-\(day).json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url)
                message = String(localized: "Gesichert: \(url.lastPathComponent)")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseRestore() {
        errorMessage = nil
        message = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard (try? JSONCoding.decoder.decode(BackupFile.self, from: data))?.app == "TV Launcher" else {
                errorMessage = String(localized: "Das ist keine TV-Launcher-Sicherung.")
                return
            }
            pendingRestore = data
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ data: Data) {
        isWorking = true
        Task {
            do {
                try await model.restore(data)
                message = String(localized: "Sicherung eingespielt")
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

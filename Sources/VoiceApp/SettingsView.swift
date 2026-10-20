import SwiftUI
import AppKit
import VoiceCore

/// Einstellungen (⌘,)
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            ShowsSettingsView()
                .tabItem { Label("Shows", systemImage: "tv") }
            PlaybackSettingsView()
                .tabItem { Label("Wiedergabe", systemImage: "play.rectangle") }
            HomeSettingsView()
                .tabItem { Label("Startseite", systemImage: "house") }
            RemoteSettingsView()
                .tabItem { Label("Fernsteuerung", systemImage: "appletvremote.gen4") }
            MacMiniSettingsView()
                .tabItem { Label("Mac mini", systemImage: "macmini") }
            BackupSettingsView()
                .tabItem { Label("Sicherung", systemImage: "externaldrive") }
        }
    }
}

// MARK: - Allgemein

struct GeneralSettingsView: View {
    @AppStorage(AppSettings.serverKey) private var server = AppSettings.defaultServer
    @AppStorage(AppSettings.languageKey) private var language = "system"
    @State private var languageAtStart = UserDefaults.standard.string(forKey: AppSettings.languageKey) ?? "system"
    @EnvironmentObject private var discovery: ServerDiscovery
    @EnvironmentObject private var model: EpisodeModel

    var body: some View {
        Form {
            Section {
                Picker("Sprache", selection: $language) {
                    Text("Wie das System").tag("system")
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                }
                .onChange(of: language) { AppLanguage.apply($0) }
                if language != languageAtStart {
                    HStack {
                        Text("Die neue Sprache gilt nach einem Neustart der App.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Jetzt neu starten") { AppLanguage.relaunch() }
                    }
                }
            } header: {
                Text("Sprache")
            }
            Section {
                TextField("Server-Adresse", text: $server, prompt: Text("http://Mac-mini.local:8081"))
                    .onSubmit { reload() }
                if discovery.servers.isEmpty {
                    Label("Suche Server im Netzwerk …", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(discovery.servers) { found in
                    HStack {
                        Label(found.name, systemImage: "macmini")
                        Spacer()
                        if found.url == server {
                            Label("Verbunden", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Verwenden") {
                                server = found.url
                                reload()
                            }
                        }
                    }
                    .help(found.url)
                }
            } header: {
                Text("Server (Mac am Fernseher)")
            } footer: {
                Text("Server im selben WLAN werden automatisch gefunden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { discovery.start() }
    }

    private func reload() {
        Task { await model.load() }
    }
}

// MARK: - Shows

struct ShowsSettingsView: View {
    @EnvironmentObject private var model: EpisodeModel
    @State private var selection: String?
    @State private var draft: Show?
    @State private var showBrowser = false
    @State private var showYouTube = false
    @AppStorage(AppSettings.showSortKey) private var showSortRaw = ShowSort.custom.rawValue
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var askPresetName = false
    @State private var presetName = ""

    private var saved: Show? { selection.flatMap(model.show) }
    private var hasChanges: Bool { draft != nil && draft != saved }

    var body: some View {
        HStack(spacing: 0) {
            showList
                .frame(width: 230)
            Divider()
            Group {
                if draft != nil {
                    editor
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "tv")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text(model.shows.isEmpty ? "Noch keine Shows – füge mit + eine hinzu." : "Wähle links eine Show.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 560)
        }
        .frame(width: 820, height: 600)
        .sheet(isPresented: $showBrowser) {
            JoynBrowserSheet { id in selection = id }
                .environmentObject(model)
        }
        .sheet(isPresented: $showYouTube) {
            YouTubeBrowserSheet { id in selection = id }
                .environmentObject(model)
        }
        .onChange(of: selection) { _ in
            draft = saved
            errorMessage = nil
        }
        .onChange(of: model.shows) { _ in
            // Nach dem Sichern / Laden den Entwurf auf den gespeicherten Stand setzen
            if draft == nil || !hasChanges { draft = saved }
        }
        .task {
            if model.shows.isEmpty { await model.load() }
            await model.loadPresets()
            if selection == nil { selection = model.shows.first?.id }
            draft = saved
        }
        .confirmationDialog("„\(saved?.name ?? "")“ löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { deleteSelected() }
        } message: {
            Text("Die Show verschwindet aus der App und der Web-App. Joyn selbst bleibt unberührt.")
        }
    }

    // MARK: Liste

    private var showList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(model.shows) { show in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(show.name)
                            Text(show.folder.map { "\(Self.kindName(show.kind)) · \($0)" } ?? Self.kindName(show.kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: Self.kindIcon(show.kind))
                    }
                    .padding(.vertical, 3)
                    .tag(show.id)
                }
                .onMove { from, to in
                    var ids = model.shows.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    // Angeordnet wird die eigene Reihenfolge – die Seitenleiste zeigt sie dann auch
                    showSortRaw = ShowSort.custom.rawValue
                    Task {
                        do {
                            try await model.reorderShows(ids)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack(spacing: 2) {
                Menu {
                    Button("Joyn-Serie oder -Film suchen …") { showBrowser = true }
                    Button("YouTube-Kanal suchen …") { showYouTube = true }
                    Button("Eigene Show mit Links") { addCustomShow() }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Show hinzufügen")

                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help("Ausgewählte Show löschen")
                Spacer()
                Text("Ziehen zum Anordnen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
            .padding(6)
        }
    }

    // MARK: Editor

    private var editor: some View {
        let show = Binding(get: { draft ?? Show.theVoice }, set: { draft = $0 })
        return VStack(spacing: 0) {
            Form {
                Section("Show") {
                    TextField("Name", text: show.name)
                    HStack {
                        TextField("Ordner", text: Binding(get: { show.wrappedValue.folder ?? "" },
                                                          set: { show.wrappedValue.folder = $0.isEmpty ? nil : $0 }),
                                  prompt: Text("Kein Ordner"))
                        Menu {
                            Button("Kein Ordner") { show.wrappedValue.folder = nil }
                            if !model.folders.isEmpty { Divider() }
                            ForEach(model.folders, id: \.self) { folder in
                                Button(folder) { show.wrappedValue.folder = folder }
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Vorhandenen Ordner wählen – oder einen neuen Namen eintippen")
                    }
                    if show.wrappedValue.kind == .joyn, let url = show.wrappedValue.joynURL {
                        LabeledContent("Joyn-Serie") {
                            Link(show.wrappedValue.id, destination: url)
                        }
                    } else if show.wrappedValue.kind == .youtube, let url = show.wrappedValue.youtubeURL {
                        LabeledContent("YouTube-Kanal") {
                            Link(show.wrappedValue.channel ?? "", destination: url)
                        }
                        Text("Die neuesten Videos (bis zu etwa 30) werden alle 30 Minuten vom Kanal geladen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Art", value: Self.kindName(show.wrappedValue.kind))
                    }
                }

                if show.wrappedValue.kind == .movies {
                    Section {
                        if show.wrappedValue.links.isEmpty {
                            Text("Noch keine Filme. Im Hauptfenster links unten „Joyn“ öffnen oder einen Filmlink einfügen.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(show.wrappedValue.links) { link in
                            HStack(spacing: 12) {
                                Thumbnail(url: link.image, cornerRadius: 6)
                                    .frame(width: 96)
                                Text(link.title)
                                Spacer()
                                Button {
                                    draft?.links.removeAll { $0.id == link.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Film aus der Liste entfernen")
                            }
                        }
                    } header: {
                        Text("Filme")
                    }
                }

                if show.wrappedValue.kind == .custom {
                    Section {
                        ForEach(show.links) { $link in
                            HStack(spacing: 8) {
                                TextField("Titel", text: $link.title)
                                    .frame(width: 170)
                                TextField("https://…", text: $link.url)
                                Button {
                                    draft?.links.removeAll { $0.id == link.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Link entfernen")
                            }
                        }
                        Button {
                            draft?.links.append(ShowLink(title: "", url: ""))
                        } label: {
                            Label("Link hinzufügen", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        Text("Links")
                    } footer: {
                        Text("Jeder Link erscheint als eigene „Folge“ und wird im Browser am Mac mini geöffnet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    KeyBindingRow(title: "Pause/Weiter", binding: show.controls.playPause)
                    KeyBindingRow(title: "Zurückspulen", binding: show.controls.back)
                    KeyBindingRow(title: "Vorspulen", binding: show.controls.forward)
                    KeyBindingRow(title: "Vollbild", binding: show.controls.fullscreen)
                    KeyBindingRow(title: "Untertitel", binding: show.controls.subtitles)
                    KeyBindingRow(title: "Lauter", binding: show.controls.volumeUp)
                    KeyBindingRow(title: "Leiser", binding: show.controls.volumeDown)
                    KeyBindingRow(title: "Ton aus/an", binding: show.controls.mute)
                } header: {
                    Text("Tasten am Mac mini")
                } footer: {
                    Text("Diese Tasten drückt der Mac mini, wenn du in der App oder Web-App die Knöpfe benutzt. Untertitel: YouTube C; Joyn hat keine Taste dafür. Lautstärke-Tasten werden nur genutzt, wenn der Mac die Lautstärke nicht selbst regeln kann (Ton über HDMI).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Nach dem Öffnen einer Folge") {
                    KeyBindingRow(title: "Automatisch drücken", binding: show.controls.start)
                    if show.wrappedValue.controls.start.kind != .none {
                        Stepper(value: show.controls.startDelay, in: 0...60, step: 1) {
                            Text("nach \(Int(show.wrappedValue.controls.startDelay)) Sekunden")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack(spacing: 10) {
                presetMenu(current: show.wrappedValue.controls)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Verwerfen") { draft = saved }
                    .disabled(!hasChanges)
                Button("Sichern") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges || isSaving)
            }
            .padding(12)
        }
    }

    /// Tasten-Presets: anwenden, aktuelle Belegung sichern, eigene löschen
    private func presetMenu(current: ShowControls) -> some View {
        let own = model.presets.filter { !$0.isBuiltIn }
        return Menu {
            Section("Vorlagen") {
                ForEach(model.presets.filter(\.isBuiltIn)) { preset in
                    Button { draft?.controls = preset.controls } label: {
                        Text(preset.name + (preset.controls == current ? "  ✓" : ""))
                    }
                    .help(preset.summary)
                }
            }
            if !own.isEmpty {
                Section("Eigene Presets") {
                    ForEach(own) { preset in
                        Button { draft?.controls = preset.controls } label: {
                            Text(preset.name + (preset.controls == current ? "  ✓" : ""))
                        }
                        .help(preset.summary)
                    }
                }
            }
            Divider()
            Button("Aktuelle Belegung als Preset sichern …") {
                presetName = own.first { $0.controls == current }?.name ?? ""
                askPresetName = true
            }
            if !own.isEmpty {
                Menu("Preset löschen") {
                    ForEach(own) { preset in
                        Button(preset.name, role: .destructive) {
                            Task {
                                do { try await model.deletePreset(preset) } catch { errorMessage = error.localizedDescription }
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Tasten-Preset", systemImage: "keyboard")
        }
        .fixedSize()
        .help("Gespeicherte Tastenbelegung übernehmen oder die aktuelle als Preset sichern")
        .alert("Tastenbelegung als Preset sichern", isPresented: $askPresetName) {
            TextField("Name, z. B. ARD Mediathek", text: $presetName)
            Button("Sichern") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task {
                    do {
                        try await model.savePreset(name: name, controls: current)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Preset steht danach bei jeder Show zur Auswahl – auch in der Web-App. Gleicher Name ersetzt ein vorhandenes Preset.")
        }
    }

    static func kindName(_ kind: Show.Kind) -> String {
        switch kind {
        case .joyn: return String(localized: "Joyn-Serie")
        case .youtube: return String(localized: "YouTube-Kanal")
        case .movies: return String(localized: "Joyn-Filme")
        case .custom: return String(localized: "Eigene Links")
        }
    }

    static func kindIcon(_ kind: Show.Kind) -> String {
        switch kind {
        case .joyn: return "play.tv.fill"
        case .youtube: return "play.rectangle.fill"
        case .movies: return "film.fill"
        case .custom: return "link"
        }
    }

    // MARK: Aktionen

    private func save() {
        guard let show = draft else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await model.saveShow(show)
                draft = model.show(show.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func addCustomShow() {
        let show = Show.custom(name: "Neue Show")
        Task {
            do {
                try await model.saveShow(show)
                selection = show.id
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        Task {
            do {
                try await model.deleteShow(id)
                selection = model.shows.first?.id
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

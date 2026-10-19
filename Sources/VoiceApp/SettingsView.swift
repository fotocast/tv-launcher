import SwiftUI
import AppKit
import VoiceCore

/// Einstellungen (⌘,): Allgemein und Shows
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            ShowsSettingsView()
                .tabItem { Label("Shows", systemImage: "tv") }
        }
    }
}

// MARK: - Allgemein

struct GeneralSettingsView: View {
    @AppStorage(AppSettings.serverKey) private var server = AppSettings.defaultServer
    @AppStorage(AppSettings.pointerSpeedKey) private var pointerSpeed = AppSettings.defaultPointerSpeed
    @EnvironmentObject private var discovery: ServerDiscovery
    @EnvironmentObject private var model: EpisodeModel

    var body: some View {
        Form {
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
            Section {
                Slider(value: $pointerSpeed, in: 0.5...4, step: 0.25) {
                    Text("Zeigertempo")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                Text("Für „Tastatur & Trackpad übertragen“: wie schnell sich der Zeiger am Fernseher bewegt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
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
            YouTubeAddSheet { id in selection = id }
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
                            Text(Self.kindName(show.kind))
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
                    Button("YouTube-Kanal hinzufügen …") { showYouTube = true }
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
                            Text("Noch keine Filme. Im Hauptfenster links unten „Joyn-Film suchen & starten …“.")
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
                } header: {
                    Text("Tasten am Mac mini")
                } footer: {
                    Text("Diese Tasten drückt der Mac mini, wenn du in der App oder Web-App die Knöpfe benutzt.")
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
                Button("Standard-Tasten") {
                    switch show.wrappedValue.kind {
                    case .joyn, .movies: draft?.controls = .joynDefault
                    case .youtube: draft?.controls = .youtubeDefault
                    case .custom: draft?.controls = .customDefault
                    }
                }
                .help(show.wrappedValue.kind == .youtube
                      ? "K, J, L, F; K nach 5 s"
                      : show.wrappedValue.kind == .custom
                        ? "Leertaste, ←, →, F; nichts beim Start"
                        : "Leertaste, ←, →, Doppelklick; Leertaste nach 10 s")
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

    static func kindName(_ kind: Show.Kind) -> String {
        switch kind {
        case .joyn: return "Joyn-Serie"
        case .youtube: return "YouTube-Kanal"
        case .movies: return "Joyn-Filme"
        case .custom: return "Eigene Links"
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

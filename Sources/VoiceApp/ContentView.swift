import SwiftUI
import AppKit
import VoiceCore

enum SidebarItem: Hashable {
    case home
    case remote
    /// Staffel einer Joyn-Show
    case season(show: String, season: Int)
    /// Alle Links einer eigenen Show
    case show(String)
    /// Gruppe einer Show, z. B. "Videos" oder "Shorts" eines YouTube-Kanals
    case group(show: String, group: String)
}

struct ContentView: View {
    @EnvironmentObject private var model: EpisodeModel
    @EnvironmentObject private var forwarder: InputForwarder
    @State private var selection: SidebarItem? = .home
    @State private var search = ""
    @State private var showMovieBrowser = false
    @State private var showYouTubeBrowser = false
    @AppStorage(AppSettings.showSortKey) private var showSortRaw = ShowSort.custom.rawValue
    @AppStorage(AppSettings.collapsedShowsKey) private var collapsedRaw = ""
    /// Rückfrage nach einem Ordnernamen: neuer Ordner für eine Show oder Umbenennen
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""

    enum FolderPrompt: Identifiable {
        case new(showID: String)
        case rename(String)
        var id: String {
            switch self {
            case .new(let id): return "new:" + id
            case .rename(let name): return "rename:" + name
            }
        }
    }

    static func allLabel(_ kind: Show.Kind) -> String {
        switch kind {
        case .youtube: return String(localized: "Videos")
        case .movies: return String(localized: "Alle Filme")
        default: return String(localized: "Alle Links")
        }
    }

    static func allIcon(_ kind: Show.Kind) -> String {
        switch kind {
        case .youtube: return "play.rectangle.on.rectangle"
        case .movies: return "film"
        default: return "link"
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .toolbar {
                    ToolbarItem {
                        if model.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                Task { await model.load(refresh: true) }
                            } label: {
                                Label("Aktualisieren", systemImage: "arrow.clockwise")
                            }
                            .help("Alle Shows neu von Joyn und YouTube laden")
                        }
                    }
                }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Suchen")
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverChanged)) { _ in
            Task { await model.load() }
        }
    }

    // MARK: - Seitenleiste

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Mac mini") {
                Label("Startseite", systemImage: "house.fill")
                    .tag(SidebarItem.home)
                Label("Fernbedienung", systemImage: "appletvremote.gen4.fill")
                    .tag(SidebarItem.remote)
            }
            ForEach(model.sidebarEntries(showSort)) { entry in
                switch entry {
                case .show(let show):
                    Section {
                        if !collapsed.contains(show.id) {
                            showItems(show)
                        }
                    } header: {
                        showHeader(show)
                    }
                case .folder(let name, let shows):
                    Section {
                        if !collapsed.contains(Self.folderKey(name)) {
                            ForEach(shows) { show in
                                folderShowRow(show)
                                if !collapsed.contains(show.id) {
                                    Group { showItems(show) }
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    } header: {
                        folderHeader(name, count: shows.count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem { sortMenu }
        }
        .safeAreaInset(edge: .bottom) {
            // Sofort abspielen: Link einfügen oder YouTube / Joyn durchsuchen
            VStack(alignment: .leading, spacing: 8) {
                Text("Sofort abspielen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                InstantPlayField(compact: true)
                HStack(spacing: 8) {
                    Button {
                        showYouTubeBrowser = true
                    } label: {
                        Label("YouTube", systemImage: "play.rectangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .help("YouTube durchsuchen und Videos am Fernseher starten")
                    Button {
                        showMovieBrowser = true
                    } label: {
                        Label("Joyn", systemImage: "tv")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Joyn durchsuchen: Filme starten, Serien hinzufügen")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .alert(folderPromptTitle, isPresented: Binding(get: { folderPrompt != nil },
                                                        set: { if !$0 { folderPrompt = nil } })) {
            TextField("Name des Ordners", text: $folderName)
            Button("Sichern") { submitFolderPrompt() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Ordner fassen Shows in der Seitenleiste und in der Web-App zusammen.")
        }
        .sheet(isPresented: $showYouTubeBrowser) {
            YouTubeBrowserSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $showMovieBrowser) {
            JoynBrowserSheet { id in selection = .show(id) }
                .environmentObject(model)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 240)
    }

    // MARK: - Shows in der Seitenleiste

    @ViewBuilder
    private func showItems(_ show: Show) -> some View {
        if show.kind == .youtube {
            let groups = model.groups(for: show)
            if groups.isEmpty {
                Label(model.isLoading ? "Lädt …" : "Keine Videos gefunden", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.self) { group in
                Label(L(group), systemImage: group == Episode.shorts
                      ? "rectangle.portrait.on.rectangle.portrait" : "play.rectangle.on.rectangle")
                    .badge(model.episodes(for: show, group: group).count)
                    .tag(SidebarItem.group(show: show.id, group: group))
            }
        } else if show.id == Show.youtubeVideosID {
            Label("Alle Videos", systemImage: "play.rectangle.on.rectangle")
                .badge(model.episodes(for: show).count)
                .tag(SidebarItem.show(show.id))
        } else if show.kind != .joyn {
            Label(Self.allLabel(show.kind), systemImage: Self.allIcon(show.kind))
                .badge(model.episodes(for: show).count)
                .tag(SidebarItem.show(show.id))
        } else if model.seasons(for: show).isEmpty {
            Label(model.isLoading ? "Lädt …" : "Keine Folgen gefunden", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        } else {
            ForEach(model.seasons(for: show), id: \.self) { season in
                Label("Staffel \(season)", systemImage: "tv")
                    .badge(model.episodes(for: show).filter { $0.season == season }.count)
                    .tag(SidebarItem.season(show: show.id, season: season))
            }
        }
    }

    /// Überschrift einer Show: Klick klappt ein/aus, Rechtsklick zum Verschieben
    private func showHeader(_ show: Show) -> some View {
        let isCollapsed = collapsed.contains(show.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { toggleCollapsed(show.id) }
        } label: {
            HStack(spacing: 6) {
                Text(show.displayName)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                    // Etwas vom Rand abrücken
                    .offset(x: -10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Ausklappen" : "Einklappen")
        .contextMenu { showMenu(show) }
    }

    /// Kontextmenü einer Show: ein-/ausklappen, verschieben, in einen Ordner legen
    @ViewBuilder
    private func showMenu(_ show: Show) -> some View {
        let isCollapsed = collapsed.contains(show.id)
        Button(isCollapsed ? "Ausklappen" : "Einklappen") { toggleCollapsed(show.id) }
        Divider()
        Button("Nach oben verschieben") { move(show, by: -1) }
            .disabled(model.shows.first?.id == show.id && showSort == .custom)
        Button("Nach unten verschieben") { move(show, by: 1) }
            .disabled(model.shows.last?.id == show.id && showSort == .custom)
        Divider()
        Menu("In Ordner legen") {
            ForEach(model.folders.filter { $0 != show.folder }, id: \.self) { folder in
                Button(folder) { Task { await model.setFolder(show.id, folder) } }
            }
            if model.folders.contains(where: { $0 != show.folder }) { Divider() }
            Button("Neuer Ordner …") {
                folderName = ""
                folderPrompt = .new(showID: show.id)
            }
        }
        if show.folder != nil {
            Button("Aus dem Ordner nehmen") { Task { await model.setFolder(show.id, nil) } }
        }
        Divider()
        Button("Alle einklappen") { setAllCollapsed(true) }
        Button("Alle ausklappen") { setAllCollapsed(false) }
    }

    static func folderKey(_ name: String) -> String { "folder:" + name }

    /// Überschrift eines Ordners: Klick klappt ein/aus, Rechtsklick zum Umbenennen/Auflösen
    private func folderHeader(_ name: String, count: Int) -> some View {
        let isCollapsed = collapsed.contains(Self.folderKey(name))
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { toggleCollapsed(Self.folderKey(name)) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "folder.fill" : "folder")
                    .foregroundStyle(Color.accentColor)
                Text(name)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                    .offset(x: -10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Ausklappen" : "Einklappen")
        .contextMenu {
            Button(isCollapsed ? "Ausklappen" : "Einklappen") { toggleCollapsed(Self.folderKey(name)) }
            Divider()
            Button("Ordner umbenennen …") {
                folderName = name
                folderPrompt = .rename(name)
            }
            Button("Ordner auflösen") { Task { await model.renameFolder(name, to: "") } }
            Divider()
            Button("Alle einklappen") { setAllCollapsed(true) }
            Button("Alle ausklappen") { setAllCollapsed(false) }
        }
    }

    /// Show innerhalb eines Ordners: Zeile mit Pfeil zum Ein-/Ausklappen
    private func folderShowRow(_ show: Show) -> some View {
        let isCollapsed = collapsed.contains(show.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { toggleCollapsed(show.id) }
        } label: {
            HStack(spacing: 6) {
                Label(show.displayName, systemImage: ShowsSettingsView.kindIcon(show.kind))
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Ausklappen" : "Einklappen")
        .contextMenu { showMenu(show) }
    }

    private var folderPromptTitle: LocalizedStringKey {
        if case .rename = folderPrompt { return "Ordner umbenennen" }
        return "Neuer Ordner"
    }

    private func submitFolderPrompt() {
        let name = folderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let prompt = folderPrompt else { return }
        Task {
            switch prompt {
            case .new(let showID): await model.setFolder(showID, name)
            case .rename(let old):
                await model.renameFolder(old, to: name)
                // Eingeklappt bleibt eingeklappt
                if collapsed.contains(Self.folderKey(old)) {
                    var ids = collapsed
                    ids.remove(Self.folderKey(old))
                    ids.insert(Self.folderKey(name))
                    setCollapsed(ids)
                }
            }
        }
    }

    /// Menü oben in der Seitenleiste: Sortierung und alle ein-/ausklappen
    private var sortMenu: some View {
        Menu {
            Picker("Sortieren", selection: $showSortRaw) {
                ForEach(ShowSort.allCases) { sort in
                    Label(sort.label, systemImage: sort.icon).tag(sort.rawValue)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Alle einklappen") { setAllCollapsed(true) }
            Button("Alle ausklappen") { setAllCollapsed(false) }
        } label: {
            Label("Shows sortieren", systemImage: "arrow.up.arrow.down")
        }
        .help("Shows sortieren, ein- und ausklappen")
    }

    private var showSort: ShowSort { ShowSort(rawValue: showSortRaw) ?? .custom }

    private var collapsed: Set<String> {
        Set(collapsedRaw.split(separator: "\n").map(String.init))
    }

    private func setCollapsed(_ ids: Set<String>) {
        collapsedRaw = ids.sorted().joined(separator: "\n")
    }

    private func toggleCollapsed(_ id: String) {
        var ids = collapsed
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        setCollapsed(ids)
    }

    private func setAllCollapsed(_ value: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            setCollapsed(value ? Set(model.shows.map(\.id) + model.folders.map(Self.folderKey)) : [])
        }
    }

    /// Verschieben gilt für die eigene Reihenfolge – bei anderer Sortierung wird auf diese umgestellt,
    /// ausgehend von der gerade sichtbaren Anordnung.
    private func move(_ show: Show, by offset: Int) {
        Task {
            if showSort != .custom {
                try? await model.reorderShows(model.sortedShows(showSort).map(\.id))
                showSortRaw = ShowSort.custom.rawValue
            }
            await model.moveShow(show.id, by: offset)
        }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var detail: some View {
        if model.shows.isEmpty, selection != .remote {
            PlaceholderView()
        } else if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            EpisodeListView(title: String(localized: "Suche"), episodes: searchResults, showContext: true)
                .playerBar()
        } else {
            switch selection ?? .home {
            case .home:
                HomeView(open: { selection = $0 })
                    .playerBar()
            case .remote:
                RemoteView()
            case .season(let showID, let season):
                let show = model.show(showID)
                EpisodeListView(title: String(localized: "\(show?.displayName ?? "") – Staffel \(season)"),
                                episodes: show.map { model.episodes(for: $0).filter { $0.season == season } } ?? [],
                                showContext: false)
                    .playerBar()
            case .group(let showID, let group):
                let show = model.show(showID)
                ThumbnailGridView(title: "\(show?.displayName ?? "") – \(L(group))",
                                  episodes: show.map { model.episodes(for: $0, group: group) } ?? [],
                                  emptyText: String(localized: "Keine \(L(group)) gefunden"),
                                  portrait: group == Episode.shorts)
                    .playerBar()
            case .show(let showID):
                let show = model.show(showID)
                let episodes = show.map { model.episodes(for: $0) } ?? []
                if showID == Show.youtubeVideosID {
                    ThumbnailGridView(title: show?.displayName ?? "", episodes: episodes,
                                      emptyText: String(localized: "Noch keine Videos – links unten einen Link einfügen oder „YouTube“ öffnen."))
                        .toolbar {
                            ToolbarItem { ClearYouTubeHistoryButton().disabled(episodes.isEmpty) }
                        }
                        .playerBar()
                } else if show?.kind == .youtube || show?.kind == .movies {
                    ThumbnailGridView(title: show?.displayName ?? "", episodes: episodes,
                                      emptyText: show?.kind == .movies
                                          ? "Noch keine Filme – links unten „Joyn“ öffnen oder einen Filmlink einfügen."
                                          : (model.isLoading ? "Lädt …" : "Keine Videos gefunden"))
                        .playerBar()
                } else {
                    EpisodeListView(title: show?.displayName ?? "", episodes: episodes, showContext: false)
                        .playerBar()
                }
            }
        }
    }

    private var searchResults: [Episode] {
        let query = Self.normalize(search.trimmingCharacters(in: .whitespaces))
        return model.allEpisodes.filter { episode in
            let showName = model.show(episode.show)?.name ?? ""
            let text = "\(showName) \(episode.code) \(episode.title) \(episode.subtitle) "
                + "staffel \(episode.season) folge \(episode.number)"
            return Self.normalize(text).contains(query)
        }
    }

    /// Joyn schreibt Umlaute als ae/oe/ue, daher wird die Suche entsprechend angeglichen.
    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
    }
}

// MARK: - Weiterschauen

struct HomeView: View {
    @EnvironmentObject private var model: EpisodeModel
    /// Wechselt in der Seitenleiste zu einem Eintrag
    var open: (SidebarItem) -> Void
    @AppStorage(AppSettings.showSortKey) private var showSortRaw = ShowSort.custom.rawValue
    @AppStorage(AppSettings.homeHiddenKey) private var hiddenRaw = ""
    @AppStorage(AppSettings.tileSizeKey) private var tileSizeRaw = TileSize.medium.rawValue

    private var hidden: Set<HomeSection> { HomeSection.hidden(hiddenRaw) }
    private func isVisible(_ section: HomeSection) -> Bool { !hidden.contains(section) }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: (TileSize(rawValue: tileSizeRaw) ?? .medium).minimumWidth), spacing: 18)]
    }

    private var shows: [Show] { model.sortedShows(ShowSort(rawValue: showSortRaw) ?? .custom) }
    private var series: [Show] { shows.filter { $0.kind == .joyn } }
    private var channels: [Show] { shows.filter { $0.kind == .youtube } }
    private var customShows: [Show] { shows.filter { $0.kind == .custom && $0.id != Show.youtubeVideosID } }
    private var movies: [Episode] { model.show(Show.moviesID).map { model.episodes(for: $0) } ?? [] }
    private var videos: [Episode] { model.show(Show.youtubeVideosID).map { model.episodes(for: $0) } ?? [] }

    /// Show für "Neu in …": die zuletzt gespielte, sonst die erste
    private var featuredShow: Show? { model.lastPlayedShow ?? model.shows.first }

    private var newest: [Episode] {
        guard let show = featuredShow else { return [] }
        let episodes = model.episodes(for: show)
        if show.kind == .youtube {
            let videos = model.episodes(for: show, group: Episode.videos)
            return Array((videos.isEmpty ? episodes : videos).prefix(6))
        }
        if show.kind != .joyn { return Array(episodes.prefix(6)) }
        guard let season = model.seasons(for: show).first else { return [] }
        return Array(episodes.filter { $0.season == season }.sorted { $0.number > $1.number }.prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if isVisible(.continueWatching) {
                    if let last = model.lastPlayed {
                        hero(last)
                    } else {
                        Text("Klicke auf eine Folge, einen Film oder ein Video – es startet am Fernseher.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                if isVisible(.newest), let show = featuredShow, !newest.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(show.kind == .joyn
                             ? String(localized: "Neu in \(show.displayName) – Staffel \(model.seasons(for: show).first ?? 0)")
                             : show.kind == .youtube ? String(localized: "Neu auf \(show.displayName)") : show.displayName)
                            .font(.title2.weight(.semibold))
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(newest, id: \.key) { episode in
                                if episode.thumbnail != nil {
                                    ThumbnailCard(episode: episode)
                                } else {
                                    EpisodeCard(episode: episode)
                                }
                            }
                        }
                    }
                }
                librarySections
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Startseite")
    }


    // MARK: Mediathek

    @ViewBuilder
    private var librarySections: some View {
        if isVisible(.series), !series.isEmpty {
            section("Serien") {
                ForEach(series) { show in
                    let season = model.seasons(for: show).first
                    ShowCard(title: show.displayName, subtitle: seriesInfo(show), image: show.image,
                             icon: "play.tv.fill", isRecent: isRecent(show)) {
                        open(season.map { .season(show: show.id, season: $0) } ?? .show(show.id))
                    }
                }
            }
        }
        if isVisible(.channels), !channels.isEmpty {
            section("YouTube-Kanäle") {
                ForEach(channels) { show in
                    let latest = model.episodes(for: show, group: Episode.videos).first ?? model.episodes(for: show).first
                    ShowCard(title: show.displayName, subtitle: channelInfo(show), image: latest?.thumbnail,
                             icon: "play.rectangle.fill", avatar: show.image, isRecent: isRecent(show)) {
                        let groups = model.groups(for: show)
                        open(groups.first.map { .group(show: show.id, group: $0) } ?? .show(show.id))
                    }
                }
            }
        }
        if isVisible(.movies), !movies.isEmpty {
            section("Filme", count: movies.count, showAll: { open(.show(Show.moviesID)) }) {
                ForEach(movies.prefix(8), id: \.key) { ThumbnailCard(episode: $0) }
            }
        }
        if isVisible(.videos), !videos.isEmpty {
            section("Zuletzt gestartete YouTube-Videos", count: videos.count,
                    showAll: { open(.show(Show.youtubeVideosID)) },
                    accessory: AnyView(ClearYouTubeHistoryButton().buttonStyle(.link))) {
                ForEach(videos.prefix(8), id: \.key) { ThumbnailCard(episode: $0) }
            }
        }
        if isVisible(.custom), !customShows.isEmpty {
            section("Eigene Shows") {
                ForEach(customShows) { show in
                    let count = model.episodes(for: show).count
                    ShowCard(title: show.displayName, subtitle: count == 1 ? String(localized: "1 Link") : String(localized: "\(count) Links"), image: nil,
                             icon: "link", isRecent: isRecent(show)) {
                        open(.show(show.id))
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, count: Int = 0, showAll: (() -> Void)? = nil,
                                        accessory: AnyView? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.title2.weight(.semibold))
                Spacer()
                if let accessory { accessory }
                if let showAll, count > 8 {
                    Button("Alle \(count) anzeigen", action: showAll)
                        .buttonStyle(.link)
                }
            }
            LazyVGrid(columns: columns, spacing: 22) {
                content()
            }
        }
    }

    private func isRecent(_ show: Show) -> Bool { model.lastPlayedRef?.show == show.id }

    private func seriesInfo(_ show: Show) -> String {
        let seasons = model.seasons(for: show)
        guard let newest = seasons.first else {
            return model.isLoading ? String(localized: "Lädt …") : String(localized: "Joyn-Serie")
        }
        let count = model.episodes(for: show).filter { $0.season == newest }.count
        return String(localized: "Staffel \(newest) · \(count) Folgen")
            + (seasons.count > 1 ? String(localized: " · \(seasons.count) Staffeln") : "")
    }

    private func channelInfo(_ show: Show) -> String {
        let videos = model.episodes(for: show, group: Episode.videos).count
        let shorts = model.episodes(for: show, group: Episode.shorts).count
        if videos + shorts == 0 { return model.isLoading ? String(localized: "Lädt …") : String(localized: "YouTube-Kanal") }
        return shorts > 0 ? String(localized: "\(videos) Videos · \(shorts) Shorts") : String(localized: "\(videos) Videos")
    }

    private func hero(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption(for: episode))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(episode.title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            if !episode.subtitle.isEmpty {
                Text(L(episode.subtitle))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Button {
                    Task { await model.play(episode) }
                } label: {
                    Label("Weiterschauen", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                if let next = model.nextEpisode {
                    Button {
                        Task { await model.play(next) }
                    } label: {
                        Label("Nächste: \(next.title)", systemImage: "forward.end.fill")
                            .font(.title3)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

                Button { open(.remote) } label: {
                    Label("Fernbedienung", systemImage: "appletvremote.gen4.fill")
                        .font(.title3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(.top, 8)
            .disabled(model.isBusy)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.55, green: 0.1, blue: 0.35), Color(red: 0.2, green: 0.1, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    private func caption(for episode: Episode) -> String {
        let show = model.show(episode.show)?.displayName.uppercased() ?? ""
        let position = episode.season > 0 ? String(localized: "STAFFEL \(episode.season), FOLGE \(episode.number)")
            : String(localized: "NR. \(episode.number)")
        return String(localized: "ZULETZT GESEHEN · \(show) · \(position)")
    }
}

/// Kachel für eine Folge (Startseite)
struct EpisodeCard: View {
    @EnvironmentObject private var model: EpisodeModel
    let episode: Episode
    @State private var isHovering = false

    var body: some View {
        Button {
            Task { await model.play(episode) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(episode.season > 0 ? "Folge \(episode.number)" : "Nr. \(episode.number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isPlaying(episode) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                            .opacity(isHovering ? 1 : 0.7)
                    }
                }
                Text(episode.title)
                    .font(.headline)
                Text(L(episode.subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isHovering ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08))
            )
            .scaleEffect(isHovering ? 1.015 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(model.isBusy)
        .help("Auf dem Mac mini abspielen")
    }
}

// MARK: - Folgenliste

struct EpisodeListView: View {
    @EnvironmentObject private var model: EpisodeModel
    let title: String
    let episodes: [Episode]
    /// Show und Staffel mit anzeigen (Suche über alle Shows)
    let showContext: Bool

    var body: some View {
        List {
            if episodes.isEmpty {
                Text("Keine Folge gefunden")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            }
            ForEach(episodes, id: \.key) { episode in
                EpisodeRow(episode: episode, showContext: showContext)
            }
        }
        .listStyle(.inset)
        .navigationTitle(title)
    }
}

struct EpisodeRow: View {
    @EnvironmentObject private var model: EpisodeModel
    let episode: Episode
    var showContext = false
    @State private var isHovering = false

    private var isLast: Bool { model.isLastPlayed(episode) }

    private var context: String {
        let show = model.show(episode.show)?.displayName ?? ""
        return episode.season > 0 ? "\(show) · S\(episode.season)" : show
    }

    var body: some View {
        Button {
            Task { await model.play(episode) }
        } label: {
            HStack(spacing: 16) {
                if episode.thumbnail != nil {
                    Thumbnail(url: episode.thumbnail, cornerRadius: 8, portrait: episode.isShort)
                        .frame(width: episode.isShort ? 63 : 112)
                } else {
                    Text(String(format: "%02d", episode.number))
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(width: 48, height: 48)
                        .background(isLast ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    if showContext {
                        Text(context)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(episode.title)
                            .font(.title3.weight(.semibold))
                        if isLast {
                            Text("zuletzt")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.25), in: Capsule())
                        }
                    }
                    if !episode.subtitle.isEmpty {
                        Text(L(episode.subtitle))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if model.isPlaying(episode) {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentColor)
                        .opacity(isHovering ? 1 : 0.55)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(isHovering ? Color.primary.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(model.isBusy)
        .help("Auf dem Mac mini abspielen")
    }
}

// MARK: - Platzhalter

struct PlaceholderView: View {
    @EnvironmentObject private var model: EpisodeModel

    var body: some View {
        VStack(spacing: 16) {
            if model.isLoading || !model.hasLoaded {
                ProgressView("Lade Shows vom Mac mini …")
                    .controlSize(.large)
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text(model.errorMessage ?? "Noch keine Shows. Füge unter Einstellungen (⌘,) → Shows eine hinzu.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Button("Erneut versuchen") {
                    Task { await model.load() }
                }
                .controlSize(.large)
                Text("Die Server-Adresse lässt sich unter Einstellungen (⌘,) ändern.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

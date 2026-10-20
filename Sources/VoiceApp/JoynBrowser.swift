import SwiftUI
import WebKit
import VoiceCore

/// Eingebauter Browser (WKWebView) mit beobachtbarer Adresse und Titel.
final class WebBrowserModel: NSObject, ObservableObject {
    let webView: WKWebView
    let start: URL
    @Published private(set) var url: URL?
    @Published private(set) var title = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    private var observations: [NSKeyValueObservation] = []

    /// Videos in der Seite sofort anhalten und stumm schalten (Vorschau in der App,
    /// abgespielt wird am Fernseher)
    private static let quietVideos = """
    (function () {
      function quiet(v) { try { v.muted = true; v.pause(); } catch (e) {} }
      document.addEventListener('play', function (e) {
        if (e.target && e.target.tagName === 'VIDEO') quiet(e.target);
      }, true);
      setInterval(function () {
        document.querySelectorAll('video').forEach(function (v) { if (!v.paused || !v.muted) quiet(v); });
      }, 800);
    })();
    """

    init(start: URL, quietVideos: Bool = false) {
        self.start = start
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if quietVideos {
            configuration.mediaTypesRequiringUserActionForPlayback = .all
            configuration.userContentController.addUserScript(
                WKUserScript(source: Self.quietVideos, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.url = view.url }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.title = view.title ?? "" }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.isLoading = view.isLoading }
            },
        ]
        webView.load(URLRequest(url: start))
    }

    func goHome() { webView.load(URLRequest(url: start)) }

    /// Adresse öffnen oder – wenn es keine ist – auf YouTube suchen. "@name" öffnet den Kanal.
    func openOrSearchYouTube(_ text: String) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        var url: URL?
        if input.hasPrefix("@"), !input.contains(" ") {
            url = URL(string: "https://www.youtube.com/\(input)")
        } else if !input.contains(" "), input.contains("."), let candidate = URL(string: input.contains("://") ? input : "https://\(input)"),
                  candidate.host != nil {
            url = candidate
        } else if input.lowercased().contains("youtu"), let id = Show.youtubeVideoID(in: input) {
            url = URL(string: "https://www.youtube.com/watch?v=\(id)")
        }
        if url == nil {
            var components = URLComponents(string: "https://www.youtube.com/results")!
            components.queryItems = [URLQueryItem(name: "search_query", value: input)]
            url = components.url
        }
        if let url { webView.load(URLRequest(url: url)) }
    }

    /// Seitentitel ohne Zusätze wie " | Joyn", " - YouTube", " online ansehen"
    var cleanTitle: String {
        // Joyn: 'Alle aktuellen Folgen "The Voice Kids" online' – der Name steht in Anführungszeichen
        for (open, close) in [("\"", "\""), ("„", "“"), ("“", "”"), ("»", "«")] {
            if let start = title.range(of: open),
               let end = title.range(of: close, range: start.upperBound..<title.endIndex),
               start.upperBound < end.lowerBound {
                return String(title[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        var name = title.components(separatedBy: " | ").first ?? title
        for separator in [" - ", " – ", " — ", ": "] {
            name = name.components(separatedBy: separator).first ?? name
        }
        for suffix in [" online ansehen", " im Stream", " streamen", " Stream", " bei Joyn"] {
            if name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("(") , let close = name.firstIndex(of: ")") {
            // YouTube setzt die Zahl ungelesener Benachrichtigungen voran, z. B. "(3) Kanal"
            name = String(name[name.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return ["joyn", "youtube"].contains(name.lowercased()) ? "" : name
    }
}

struct WebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Navigationsleiste über dem Browser
struct BrowserToolbar: View {
    @ObservedObject var browser: WebBrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack)
            Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward)
            Button {
                if browser.isLoading { browser.webView.stopLoading() } else { browser.webView.reload() }
            } label: {
                Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
            }
            Button { browser.goHome() } label: { Image(systemName: "house") }
            Text(browser.url?.absoluteString ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            Button("Fertig") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
        .padding(10)
    }
}

// MARK: - Joyn: Serien und Filme

struct JoynBrowserSheet: View {
    @EnvironmentObject private var model: EpisodeModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = WebBrowserModel(start: URL(string: "https://www.joyn.de/")!)
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    /// Wird nach dem Hinzufügen mit der ID der neuen bzw. geänderten Show aufgerufen
    var onAdded: (String) -> Void = { _ in }

    private var series: String? { browser.url.flatMap(Show.joynSeries(in:)) }
    private var movie: String? { browser.url.flatMap(Show.joynMovie(in:)) }

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(browser: browser)
            Divider()
            WebView(webView: browser.webView)
            Divider()
            footer
                .padding(14)
                .background(.bar)
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 760)
        .onChange(of: browser.url) { _ in updateName() }
        .onChange(of: browser.title) { _ in updateName() }
    }

    private func updateName() {
        errorMessage = nil
        if series != nil {
            name = browser.cleanTitle.isEmpty ? humanized(series ?? "") : browser.cleanTitle
        }
    }

    private func humanized(_ slug: String) -> String {
        slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if let movie {
                movieFooter(movie)
            } else if let series {
                seriesFooter(series)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Öffne auf Joyn die Seite einer Serie oder eines Films – dann kannst du sie hier hinzufügen oder den Film direkt starten.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func seriesFooter(_ series: String) -> some View {
        let exists = model.show(series) != nil
        Image(systemName: exists ? "checkmark.circle.fill" : "plus.circle.fill")
            .font(.title2)
            .foregroundStyle(exists ? .green : Color.accentColor)
        VStack(alignment: .leading, spacing: 2) {
            TextField("Name der Show", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            Text("Serie · joyn.de/serien/\(series)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        errorText
        Spacer()
        if isWorking { ProgressView().controlSize(.small) }
        Button(exists ? "Schon hinzugefügt" : "Show hinzufügen") {
            run {
                try await model.saveShow(.joyn(series: series, name: name))
                onAdded(series)
                dismiss()
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(exists || isWorking || name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder
    private func movieFooter(_ movie: String) -> some View {
        let saved = model.show(Show.moviesID)?.links.contains { $0.id == movie } ?? false
        Image(systemName: "film.fill")
            .font(.title2)
            .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 2) {
            Text(browser.cleanTitle.isEmpty ? humanized(movie) : browser.cleanTitle)
                .font(.headline)
                .lineLimit(1)
            Text("Film · joyn.de/filme/\(movie)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        errorText
        Spacer()
        if isWorking { ProgressView().controlSize(.small) }
        Button(saved ? "In Filmen gemerkt" : "Zu Filmen hinzufügen") {
            run {
                try await model.addMovie(movie, play: false)
                onAdded(Show.moviesID)
            }
        }
        .controlSize(.large)
        .disabled(saved || isWorking)
        Button {
            run {
                try await model.addMovie(movie, play: true)
                onAdded(Show.moviesID)
                dismiss()
            }
        } label: {
            Label("Jetzt am Fernseher abspielen", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(isWorking)
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

// MARK: - YouTube: durchsuchen, Videos starten, Kanäle hinzufügen

/// Eingebauter YouTube-Browser. Auf einer Videoseite: am Fernseher abspielen, merken oder den Kanal
/// hinzufügen; auf einer Kanalseite: Kanal hinzufügen. Videos laufen hier nur stumm und angehalten.
struct YouTubeBrowserSheet: View {
    @EnvironmentObject private var model: EpisodeModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = WebBrowserModel(start: URL(string: "https://www.youtube.com/")!,
                                                       quietVideos: true)
    @State private var query = ""
    @State private var name = ""
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    /// Wird nach dem Hinzufügen eines Kanals bzw. Videos mit der ID der Show aufgerufen
    var onAdded: (String) -> Void = { _ in }

    private var channel: String? { browser.url.flatMap(Show.youtubeChannel(in:)) }
    /// Offenes Video (watch?v=, /shorts/, /live/)
    private var video: String? {
        guard let url = browser.url, Show.youtubeVideoID(in: url.absoluteString) != nil,
              url.path == "/watch" || url.path.hasPrefix("/shorts/") || url.path.hasPrefix("/live/") else { return nil }
        return url.absoluteString
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(browser: browser)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("YouTube durchsuchen, @Kanal oder Link einfügen", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { browser.openOrSearchYouTube(query) }
                Button("Suchen") { browser.openOrSearchYouTube(query) }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            Divider()
            WebView(webView: browser.webView)
            Divider()
            footer
                .padding(14)
                .background(.bar)
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 780)
        .onChange(of: browser.url) { _ in
            errorMessage = nil
            message = nil
            name = channel != nil ? browser.cleanTitle : ""
        }
        .onChange(of: browser.title) { _ in
            if channel != nil { name = browser.cleanTitle }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if let video {
                videoFooter(video)
            } else if let channel {
                channelFooter(channel)
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                statusText(default: "Öffne ein Video, um es am Fernseher abzuspielen – oder einen Kanal, um ihn hinzuzufügen.")
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
            }
        }
    }

    @ViewBuilder
    private func videoFooter(_ video: String) -> some View {
        Image(systemName: "play.rectangle.fill")
            .font(.title2)
            .foregroundStyle(.red)
        VStack(alignment: .leading, spacing: 2) {
            Text(browser.cleanTitle.isEmpty ? "YouTube-Video" : browser.cleanTitle)
                .font(.headline)
                .lineLimit(1)
            statusText(default: "Die Vorschau hier bleibt stumm – abgespielt wird am Fernseher.")
                .font(.caption)
        }
        Spacer()
        if isWorking { ProgressView().controlSize(.small) }
        Menu {
            Button("Video merken (in „YouTube-Videos“)") {
                run(done: "Gemerkt in „YouTube-Videos“") {
                    try await model.addYouTubeVideo(video, play: false)
                    onAdded(Show.youtubeVideosID)
                }
            }
            Button("Kanal dieses Videos hinzufügen") { addChannel(video) }
        } label: {
            Label("Mehr", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isWorking)
        Button {
            run(done: "Läuft am Fernseher") {
                try await model.addYouTubeVideo(video, play: true)
                onAdded(Show.youtubeVideosID)
            }
        } label: {
            Label("Am Fernseher abspielen", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(isWorking)
    }

    @ViewBuilder
    private func channelFooter(_ channel: String) -> some View {
        Image(systemName: "person.crop.rectangle.stack.fill")
            .font(.title2)
            .foregroundStyle(.red)
        VStack(alignment: .leading, spacing: 2) {
            TextField("Name (leer = Kanalname)", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            statusText(default: "Kanal erkannt – neue Videos und Shorts erscheinen in der App")
                .font(.caption)
        }
        Spacer()
        if isWorking { ProgressView().controlSize(.small) }
        Button("Kanal hinzufügen") { addChannel(channel) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isWorking)
    }

    /// Fehler (orange), Erfolgsmeldung (grün) oder der Hinweis
    @ViewBuilder
    private func statusText(default text: String) -> some View {
        if let errorMessage {
            Text(errorMessage).foregroundStyle(.orange).lineLimit(2)
        } else if let message {
            Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(1)
        } else {
            Text(text).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private func addChannel(_ input: String) {
        let show = Show.youtube(channel: input, name: name.trimmingCharacters(in: .whitespaces))
        run(done: "Kanal hinzugefügt") {
            try await model.saveShow(show)
            onAdded(show.id)
        }
    }

    private func run(done: String, _ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        message = nil
        Task {
            do {
                try await action()
                message = done
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

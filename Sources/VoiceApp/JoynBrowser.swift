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

    init(start: URL) {
        self.start = start
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
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

// MARK: - YouTube-Kanal

struct YouTubeAddSheet: View {
    @EnvironmentObject private var model: EpisodeModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = WebBrowserModel(start: URL(string: "https://www.youtube.com/")!)
    @State private var address = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    var onAdded: (String) -> Void = { _ in }

    /// Kanal aus der offenen Seite: Kanalseite oder Video (der Server ermittelt dann den Kanal)
    private var detected: String? {
        guard let url = browser.url else { return nil }
        if let channel = Show.youtubeChannel(in: url) { return channel }
        if url.path == "/watch" || url.path.hasPrefix("/shorts/") { return url.absoluteString }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(browser: browser)
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("Kanal-Adresse oder @Name, z. B. https://www.youtube.com/@tagesschau", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add(address) }
                Button("Hinzufügen") { add(address) }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
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
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 760)
        .onChange(of: browser.url) { _ in
            errorMessage = nil
            if detected != nil, Show.youtubeChannel(in: browser.url!) != nil { name = browser.cleanTitle }
            else { name = "" }
        }
        .onChange(of: browser.title) { _ in
            if let url = browser.url, Show.youtubeChannel(in: url) != nil { name = browser.cleanTitle }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if let detected {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name (leer = Kanalname)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                    Text(Show.youtubeChannel(in: browser.url!) != nil ? "Kanal erkannt" : "Video erkannt – sein Kanal wird hinzugefügt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.orange).lineLimit(2)
                }
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Kanal hinzufügen") { add(detected) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.orange).lineLimit(2)
                } else {
                    Text("Öffne einen YouTube-Kanal (oder ein Video davon) – oder gib oben die Kanal-Adresse ein.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
            }
        }
    }

    private func add(_ channel: String) {
        let input = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let show = Show.youtube(channel: input, name: name.trimmingCharacters(in: .whitespaces))
                try await model.saveShow(show)
                onAdded(show.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

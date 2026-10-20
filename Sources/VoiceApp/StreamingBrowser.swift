import SwiftUI
import VoiceCore

/// Eingebauter Browser für Netflix, Prime Video und Disney+. Man meldet sich hier einmal an (bleibt gespeichert)
/// und kann dann auf einer Titelseite die Serie hinzufügen, den Titel merken oder ihn sofort am Fernseher starten.
struct StreamingBrowserSheet: View {
    @EnvironmentObject private var model: EpisodeModel
    let service: Show.Kind
    @StateObject private var browser: WebBrowserModel
    @State private var name = ""
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    var onAdded: (String) -> Void = { _ in }

    init(service: Show.Kind, onAdded: @escaping (String) -> Void = { _ in }) {
        self.service = service
        self.onAdded = onAdded
        let start: String
        switch service {
        case .netflix: start = "https://www.netflix.com/browse"
        case .prime: start = "https://www.primevideo.com/"
        default: start = "https://www.disneyplus.com/"
        }
        _browser = StateObject(wrappedValue: WebBrowserModel(start: URL(string: start)!, quietVideos: true))
    }

    /// Erkannter Titel auf der offenen Seite (Adresse)
    private var detected: String? {
        guard let url = browser.url?.absoluteString else { return nil }
        switch service {
        case .netflix: return Show.netflixID(in: url) != nil ? url : nil
        case .prime: return Show.primeID(in: url) != nil ? url : nil
        default:
            return Show.isDisneyLink(url) && (url.contains("entity-") || url.contains("/play/") || url.contains("/video/"))
                ? url : nil
        }
    }

    /// Seitentitel ohne Zusätze wie „| Netflix“ oder „Prime Video:“
    private var cleanTitle: String {
        var title = browser.title
        for prefix in ["Prime Video: ", "Netflix: "] where title.hasPrefix(prefix) { title.removeFirst(prefix.count) }
        for separator in [" | ", " – ", " - "] {
            if let range = title.range(of: separator) { title = String(title[..<range.lowerBound]) }
        }
        title = title.replacingOccurrences(of: " ansehen", with: "").trimmingCharacters(in: .whitespaces)
        return ["netflix", "prime video", "disney+", "startseite", "home"].contains(title.lowercased()) ? "" : title
    }

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
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 780)
        .onChange(of: browser.url) { _ in
            message = nil
            errorMessage = nil
            name = cleanTitle
        }
        .onChange(of: browser.title) { _ in name = cleanTitle }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: ShowsSettingsView.kindIcon(service))
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            if let link = detected {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name (leer = automatisch)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                    status(default: "Titel erkannt")
                }
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                if service == .disney {
                    Button("Merken") { run(done: String(localized: "Gemerkt")) { try await model.addStreamLink(link, name: name, play: false) } }
                        .disabled(isWorking)
                } else {
                    Button("Serie hinzufügen") {
                        run(done: String(localized: "Hinzugefügt – Folgen erscheinen in der Seitenleiste")) {
                            if let id = try await model.addShow(kind: service, input: link, name: name) { onAdded(id) }
                        }
                    }
                    .disabled(isWorking)
                    .help("Alle Staffeln und Folgen in die App holen")
                }
                Button {
                    run(done: String(localized: "Läuft am Fernseher")) {
                        try await model.addStreamLink(link, name: name.isEmpty ? nil : name, play: true)
                    }
                } label: {
                    Label("Am Fernseher abspielen", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            } else {
                status(default: service == .disney
                       ? "Melde dich an und öffne einen Film oder eine Serie – dann kannst du sie merken oder sofort abspielen."
                       : "Melde dich an und öffne eine Serie oder einen Film – dann kannst du sie hinzufügen oder sofort abspielen.")
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func status(default text: LocalizedStringKey) -> some View {
        if let errorMessage {
            Text(errorMessage).foregroundStyle(.orange).lineLimit(2)
        } else if let message {
            Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(1)
        } else {
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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

extension Show.Kind: Identifiable {
    public var id: String { rawValue }
}

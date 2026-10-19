import Foundation
import Network
import VoiceCore

/// Sucht per Bonjour nach TV-Launcher-Servern im lokalen Netz.
/// Ist noch keine Server-Adresse eingestellt, wird der erste gefundene Server übernommen.
@MainActor
final class ServerDiscovery: ObservableObject {
    struct Server: Identifiable, Hashable {
        /// Computername, z. B. "Wohnzimmer-Mac"
        let name: String
        /// z. B. "http://Wohnzimmer-Mac.local:8081"
        let url: String
        var id: String { url }
    }

    @Published private(set) var servers: [Server] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Discovery.serviceType, domain: nil),
                                using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap(Self.server).sorted { $0.name < $1.name }
            Task { @MainActor in self?.update(found) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func update(_ found: [Server]) {
        servers = Array(Set(found)).sorted { $0.name < $1.name }
        let stored = UserDefaults.standard.string(forKey: AppSettings.serverKey) ?? ""
        if stored.trimmingCharacters(in: .whitespaces).isEmpty, let first = servers.first {
            UserDefaults.standard.set(first.url, forKey: AppSettings.serverKey)
            NotificationCenter.default.post(name: .serverChanged, object: nil)
        }
    }

    private nonisolated static func server(_ result: NWBrowser.Result) -> Server? {
        guard case .service(let name, _, _, _) = result.endpoint,
              case .bonjour(let txt) = result.metadata,
              let host = txt["host"], let port = txt["port"] else { return nil }
        return Server(name: name, url: "http://\(host):\(port)")
    }
}

extension Notification.Name {
    /// Die Server-Adresse wurde automatisch gesetzt → neu laden
    static let serverChanged = Notification.Name("serverChanged")
}

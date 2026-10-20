import Foundation
import VoiceCore

// TV Launcher Server – läuft auf dem Mac mini.
// Optionen: --port 8081  --browser Firefox  --space-delay 10  --public <Ordner>  --data <Ordner>

setvbuf(stdout, nil, _IOLBF, 0)

let config = ServerConfig.fromArguments()
try? FileManager.default.createDirectory(at: config.dataDir, withIntermediateDirectories: true)

let catalogs = CatalogStore(dataDir: config.dataDir)
let state = ServerState(file: config.dataDir.appendingPathComponent("daten.json"),
                        legacyFile: config.dataDir.appendingPathComponent("status.json"),
                        defaultStartDelay: config.spaceDelay)
let router = Router(catalogs: catalogs, state: state, config: config)

do {
    let server = try HTTPServer(port: config.port) { request in
        await router.handle(request)
    }
    server.start()
    serverLog("TV Launcher Server auf Port \(config.port), Browser: \(config.browser)")
    serverLog("Web-Ordner: \(config.publicDir.path)")
    Player.requestAccessibility()
    Task {
        let browser = await state.settings.browser ?? config.browser
        if browser.lowercased() == "firefox" { FirefoxSetup.apply() }
    }

    // Nach dem Hochfahren ohne Tastatur erscheint oft der Bluetooth-Assistent:
    // die ersten 5 Minuten regelmäßig ausblenden.
    Task.detached {
        for _ in 0..<100 {
            Player.hideBluetoothAssistant()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    // Folgenlisten aller Joyn- und YouTube-Shows beim Start im Hintergrund vorladen
    Task {
        await router.fillMissingImages()
        for show in await state.showsResponse.shows where show.kind != .custom {
            _ = await router.handle(HTTPRequest(method: "GET", path: "/api/episodes", query: "show=\(show.id)",
                                                headers: [:], body: Data()))
        }
    }
    withExtendedLifetime(server) {
        dispatchMain()
    }
} catch {
    serverLog("Server konnte nicht starten: \(error)")
    exit(1)
}

import Foundation

func serverLog(_ message: String) {
    let time = ISO8601DateFormatter().string(from: Date())
    print("[\(time)] \(message)")
}

struct ServerConfig {
    var port: UInt16 = 8081
    var browser = "Firefox"
    /// Wartezeit bis zur Start-Taste für The Voice beim ersten Start (danach pro Show in den Einstellungen)
    var spaceDelay: Double = 10
    /// Vor jedem Start den Browser beenden, damit sich keine alten Tabs ansammeln (`--close-old-tabs false` = aus)
    var closeOldTabs = true
    var publicDir: URL
    var dataDir: URL

    static func fromArguments() -> ServerConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var config = ServerConfig(
            publicDir: home.appendingPathComponent("TheVoiceServer/Public"),
            dataDir: home.appendingPathComponent("Library/Application Support/TheVoiceServer")
        )
        var args = Array(CommandLine.arguments.dropFirst())
        while args.count >= 2 {
            let key = args.removeFirst()
            let value = args.removeFirst()
            switch key {
            case "--port": if let port = UInt16(value) { config.port = port }
            case "--browser": config.browser = value
            case "--space-delay": if let delay = Double(value) { config.spaceDelay = delay }
            case "--public": config.publicDir = URL(fileURLWithPath: value)
            case "--data": config.dataDir = URL(fileURLWithPath: value)
            case "--close-old-tabs": config.closeOldTabs = !["false", "0", "nein", "no"].contains(value.lowercased())
            default: serverLog("Unbekannte Option \(key)")
            }
        }
        return config
    }
}

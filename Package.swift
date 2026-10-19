// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TheVoice",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VoiceServer", targets: ["VoiceServer"]),
        .executable(name: "VoiceApp", targets: ["VoiceApp"]),
    ],
    targets: [
        // Gemeinsame Logik: Folgen-Modell, API-Typen, Joyn-Katalog
        .target(name: "VoiceCore"),
        // Läuft auf dem Mac mini: HTTP-API + später die Web-App (Ordner Public)
        .executableTarget(name: "VoiceServer", dependencies: ["VoiceCore"]),
        // SwiftUI-App für das MacBook, spricht nur mit dem Server
        .executableTarget(name: "VoiceApp", dependencies: ["VoiceCore"]),
    ]
)

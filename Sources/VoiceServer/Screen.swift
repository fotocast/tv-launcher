import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Bildschirmfoto des Mac mini für den Modus "Bildschirm anklicken" der Mac-App.
/// Braucht am Mac mini die Berechtigung "Bildschirm- und Systemaudioaufnahme" für VoiceServer.
enum Screen {
    struct PermissionError: LocalizedError {
        var errorDescription: String? {
            "VoiceServer fehlt am Mac mini die Berechtigung „Bildschirm- und Systemaudioaufnahme“ "
                + "(Systemeinstellungen > Datenschutz & Sicherheit)."
        }
    }

    struct CaptureError: LocalizedError {
        let detail: String
        var errorDescription: String? { "Bildschirmfoto fehlgeschlagen: \(detail)" }
    }

    /// Fragt beim ersten Mal nach der Berechtigung, damit VoiceServer in der Liste erscheint.
    static func requestAccessIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        return false
    }

    /// JPEG des Hauptbildschirms, längste Seite höchstens `maxSize` Pixel.
    static func capture(maxSize: Int = 1600) throws -> Data {
        guard requestAccessIfNeeded() else { throw PermissionError() }
        // Bei ausgeschaltetem Display wäre das Bild schwarz
        Player.wakeDisplay()

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("thevoice-screen-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x ohne Ton, -m nur Hauptbildschirm
        process.arguments = ["-x", "-m", "-t", "jpg", file.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil) else {
            throw CaptureError(detail: "screencapture endete mit Status \(process.terminationStatus)")
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw CaptureError(detail: "Bild konnte nicht gelesen werden")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CaptureError(detail: "JPEG konnte nicht erzeugt werden")
        }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError(detail: "JPEG konnte nicht gespeichert werden")
        }
        return data as Data
    }
}

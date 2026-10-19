import Foundation
import AppKit
import ApplicationServices
import IOKit.pwr_mgt
import VoiceCore

/// Öffnet Adressen im Browser des angemeldeten Benutzers und steuert den Player
/// per Tastendruck oder Doppelklick (CGEvent).
/// Tasten und Klicks brauchen am Mac mini die Berechtigung "Bedienungshilfen" für VoiceServer.
enum Player {
    struct OpenError: LocalizedError {
        let status: Int32
        var errorDescription: String? { "open endete mit Status \(status)" }
    }

    struct PermissionError: LocalizedError {
        var errorDescription: String? {
            "VoiceServer fehlt am Mac mini die Berechtigung „Bedienungshilfen“ "
                + "(Systemeinstellungen > Datenschutz & Sicherheit)."
        }
    }

    struct NoBindingError: LocalizedError {
        let action: String
        let show: String
        var errorDescription: String? { "Für „\(action)“ ist bei \(show) keine Taste festgelegt." }
    }

    static func open(_ url: URL, browser: String) throws {
        wakeDisplay()
        try runOpen(browser.isEmpty ? [url.absoluteString] : ["-a", browser, url.absoluteString])
    }

    /// Holt den Browser nach vorn und löst die Tastenbelegung aus.
    static func perform(_ binding: KeyBinding, browser: String) throws {
        guard AXIsProcessTrusted() else { throw PermissionError() }
        wakeDisplay()
        if !browser.isEmpty { try? runOpen(["-a", browser]) }
        usleep(300_000)
        switch binding.kind {
        case .key:
            if let code = binding.keyCode { pressKey(code, flags: binding.modifiers ?? 0) }
        case .doubleClick:
            doubleClickScreenCenter()
        case .none:
            break
        }
        serverLog("Player: \(binding.label)")
    }

    /// Blendet den Bluetooth-Assistenten aus, der beim Start ohne angeschlossene Tastatur
    /// erscheint und sonst Firefox verdeckt. Die Kopplung vorhandener Tastaturen bleibt unberührt.
    static func hideBluetoothAssistant() {
        let pgrep = Process()
        let pipe = Pipe()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "BluetoothSetupAssistant"]
        pgrep.standardOutput = pipe
        guard (try? pgrep.run()) != nil else { return }
        pgrep.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for pid in output.split(separator: "\n").compactMap({ pid_t($0) }) {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isHidden else { continue }
            if app.hide() {
                serverLog("Bluetooth-Assistent ausgeblendet.")
            } else if app.terminate() {
                serverLog("Bluetooth-Assistent beendet.")
            }
        }
    }

    /// Meldet dem System "Benutzer ist aktiv": weckt das Display auf und beendet den Bildschirmschoner.
    /// War das Display aus, kurz warten, bis das Bild wieder da ist.
    static func wakeDisplay() {
        hideBluetoothAssistant()
        let wasAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        var assertion: IOPMAssertionID = 0
        let result = IOPMAssertionDeclareUserActivity("TV Launcher" as CFString, kIOPMUserActiveLocal, &assertion)
        if result == kIOReturnSuccess {
            IOPMAssertionRelease(assertion)
        }
        if wasAsleep {
            serverLog("Display aufgeweckt.")
            usleep(1_500_000)
        }
    }

    /// Fragt beim Start einmal nach der Berechtigung, damit VoiceServer in der Liste
    /// "Bedienungshilfen" erscheint.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            serverLog("Hinweis: Für Tasten und Fernbedienung braucht VoiceServer die Berechtigung „Bedienungshilfen“.")
        }
    }

    private static func pressKey(_ code: CGKeyCode, flags: UInt64) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown)
            event?.flags = CGEventFlags(rawValue: flags)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func doubleClickScreenCenter() {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(50_000)
        for clickState in [1, 2] as [Int64] {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                    mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: clickState)
                event?.post(tap: .cghidEventTap)
            }
            usleep(60_000)
        }
    }

    private static func runOpen(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw OpenError(status: process.terminationStatus) }
    }
}

/// Drückt nach dem Öffnen einer Folge verzögert die Start-Taste der Show (Joyn: Leertaste).
/// Wird in der Wartezeit schon die nächste Folge gewählt, zählt nur die letzte.
/// Ein Steuerbefehl in der Wartezeit bricht das automatische Drücken ab.
actor AutoPlay {
    private var generation = 0

    func press(_ binding: KeyBinding, after seconds: Double, browser: String) async {
        generation += 1
        let mine = generation
        try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
        guard mine == generation else { return }
        do {
            try Player.perform(binding, browser: browser)
        } catch {
            serverLog("Start-Taste nicht gesendet: \(error.localizedDescription)")
        }
    }

    func cancel() {
        generation += 1
    }
}

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

    /// - Parameter closeOldTabs: Browser vorher sauber beenden, damit nur das neue Video offen ist
    ///   (Anmeldungen bleiben erhalten; Firefox öffnet dank `FirefoxSetup` keine alten Tabs wieder).
    static func open(_ url: URL, browser: String, closeOldTabs: Bool = false) throws {
        wakeDisplay()
        if closeOldTabs, !browser.isEmpty { quitBrowser(browser) }
        try runOpen(browser.isEmpty ? [url.absoluteString] : ["-a", browser, url.absoluteString])
    }

    /// Beendet den Browser sauber (wie ⌘Q) und wartet bis zu 6 s. Hängt er danach noch (z. B. an der
    /// Rückfrage „Tabs schließen?“), wird er hart beendet – alte Tabs werden ohnehin nicht wiederhergestellt
    /// (`FirefoxSetup`), Anmeldungen bleiben gespeichert.
    static func quitBrowser(_ browser: String) {
        let apps = runningApps(named: browser)
        guard !apps.isEmpty else { return }
        // `isTerminated` bleibt in einem Dienst ohne App-Lauf veraltet – daher direkt den Prozess prüfen
        let alive = { apps.contains { kill($0.processIdentifier, 0) == 0 } }
        func waitUntilGone(_ tenths: Int) {
            for _ in 0..<tenths where alive() { usleep(100_000) }
        }
        let accepted = apps.map { $0.terminate() }
        if accepted.contains(false) { serverLog("\(browser): Beenden-Anfrage abgelehnt.") }
        waitUntilGone(60)
        if alive() {
            serverLog("\(browser) reagiert nicht auf Beenden – beende hart.")
            apps.forEach { $0.forceTerminate() }
            waitUntilGone(30)
        }
        serverLog(alive() ? "\(browser) läuft noch – öffne trotzdem." : "\(browser) beendet (alte Tabs geschlossen).")
        usleep(300_000)
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

    // MARK: - Lautstärke & Display

    /// Aktuelle Lautstärke (0…100) und ob stumm – über AppleScript (`volume settings`)
    static func volume() -> VolumeResponse? {
        guard let output = runAppleScript("set v to get volume settings\nreturn (output volume of v as text) & \",\" & (output muted of v as text)"),
              case let parts = output.split(separator: ","), parts.count == 2,
              let volume = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))   // HDMI: "missing value"
        else { return nil }
        return VolumeResponse(volume: volume, muted: parts[1].trimmingCharacters(in: .whitespacesAndNewlines) == "true")
    }

    static func setVolume(_ value: Int) {
        _ = runAppleScript("set volume output volume \(min(max(value, 0), 100)) without output muted")
    }

    static func setMuted(_ muted: Bool) {
        _ = runAppleScript("set volume output muted \(muted)")
    }

    /// Bildschirm sofort ausschalten (Sleep-Timer)
    static func displaySleep() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
        process.waitUntilExit()
    }

    private static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return process.terminationStatus == 0 ? output : nil
    }

    /// Laufende Instanzen einer App, z. B. "Firefox" → /Applications/Firefox.app/Contents/MacOS/…
    /// (über `ps`, weil `NSWorkspace.runningApplications` in einem Dienst ohne App-Lauf nicht aktuell bleibt)
    private static func runningApps(named name: String) -> [NSRunningApplication] {
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-x", "-o", "pid=,comm="]
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        let marker = "/\(name).app/Contents/MacOS/"
        return output.split(separator: "\n").compactMap { line -> NSRunningApplication? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let range = parts[1].range(of: marker), let pid = pid_t(parts[0]) else { return nil }
            // Nur die Haupt-App (Hilfsprozesse liegen in Unterordnern wie …/Contents/MacOS/plugin-container.app)
            guard !parts[1][range.upperBound...].contains("/"),
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
            else { return nil }   // Hilfsprozesse wie crashhelper haben kein Fenster
            return app
        }
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
        await sequence([(binding, seconds)], browser: browser)
    }

    /// Mehrere Tasten nacheinander, z. B. Start-Taste nach 10 s und danach Vollbild nach weiteren 3 s.
    /// Jede Wartezeit zählt ab dem vorigen Schritt.
    func sequence(_ steps: [(KeyBinding, Double)], browser: String) async {
        generation += 1
        let mine = generation
        for (binding, seconds) in steps where binding.kind != .none {
            try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            guard mine == generation else { return }
            do {
                try Player.perform(binding, browser: browser)
            } catch {
                serverLog("Taste nicht gesendet: \(error.localizedDescription)")
                return
            }
        }
    }

    func cancel() {
        generation += 1
    }
}

/// Sleep-Timer: nach Ablauf pausieren (Taste „Pause/Weiter“ der laufenden Show) und Display ausschalten.
actor SleepTimer {
    private(set) var endsAt: Date?
    private var task: Task<Void, Never>?

    func start(minutes: Int, action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        guard minutes > 0 else {
            endsAt = nil
            task = nil
            return
        }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        endsAt = end
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await action()
            await self?.finished(end)
        }
    }

    private func finished(_ end: Date) {
        if endsAt == end { endsAt = nil }
    }
}

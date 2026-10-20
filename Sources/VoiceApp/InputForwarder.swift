import AppKit
import VoiceCore

/// Fernsteuerung des Mac mini aus der Mac-App, in zwei Modi:
///
/// **Zeiger steuern** (`.pointer`): überträgt alle Tastatur- und Trackpad-Eingaben.
/// - Der Mauszeiger wird auf dem MacBook festgehalten und ausgeblendet, Bewegungen gehen
///   nur noch an den Mac mini (wie bei Spielen).
/// - Beenden mit ⌘⎋ oder automatisch, sobald die App in den Hintergrund geht (z. B. ⌘⇥).
/// - Gesten mit drei/vier Fingern und Tasten wie ⌘⇥ behält macOS für sich.
///
/// **Bildschirm anklicken** (`.screen`): zeigt ein Bildschirmfoto des Mac mini (Abstand einstellbar, Standard 60 s, und nach jedem
/// Klick neu). Ein Klick ins Bild setzt den Zeiger erst dann an die Stelle und klickt dort – man muss
/// dem verzögerten Zeiger nicht zusehen. Tasten werden weiterhin übertragen; Beenden mit ⌘⎋.
@MainActor
final class InputForwarder: ObservableObject {
    enum Mode: String, CaseIterable {
        case pointer
        case screen
    }

    /// Ereignisse aus dem Bildschirmfoto; Punkte 0…1 relativ zum Bild
    enum ScreenEvent {
        case down(button: Int, clicks: Int, at: CGPoint)
        case drag(at: CGPoint)
        case up(button: Int, clicks: Int, at: CGPoint)
        case scroll(dx: Double, dy: Double, at: CGPoint, ended: Bool)
    }

    @Published var mode: Mode = .pointer
    @Published private(set) var isActive = false
    /// Modus der laufenden Übertragung (die Auswahl `mode` lässt sich währenddessen nicht ändern)
    @Published private(set) var activeMode: Mode?
    @Published private(set) var errorMessage: String?
    @Published private(set) var screenshot: NSImage?
    @Published private(set) var screenshotDate: Date?
    @Published private(set) var isLoadingScreenshot = false

    private var client: APIClient?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var queue: [InputEvent] = []
    private var isSending = false
    private var pointerSpeed = AppSettings.defaultPointerSpeed
    private var timer: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?
    private var lastPoint: CGPoint?

    /// Tastencode → zugehöriger Modifier (für "flagsChanged"-Ereignisse)
    private static let modifierForKey: [UInt16: NSEvent.ModifierFlags] = [
        55: .command, 54: .command,
        56: .shift, 60: .shift,
        58: .option, 61: .option,
        59: .control, 62: .control,
        57: .capsLock, 63: .function,
    ]

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard !isActive else { return }
        guard let client = APIClient.fromSettings() else {
            errorMessage = String(localized: "Ungültige Server-Adresse. Öffne die Einstellungen mit ⌘,")
            return
        }
        self.client = client
        let speed = UserDefaults.standard.double(forKey: AppSettings.pointerSpeedKey)
        pointerSpeed = speed > 0 ? speed : AppSettings.defaultPointerSpeed
        errorMessage = nil
        isActive = true
        activeMode = mode

        // Im Bildschirm-Modus nur Tasten abfangen – Klicks kommen aus der Bildansicht
        let mask: NSEvent.EventTypeMask = mode == .screen
            ? [.keyDown, .keyUp, .flagsChanged]
            : [.keyDown, .keyUp, .flagsChanged,
               .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
               .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
               .scrollWheel]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            // Läuft auf dem Main Thread
            let swallowed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallowed ? nil : event
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            },
        ]
        switch mode {
        case .pointer:
            observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
            captureCursor()
        case .screen:
            lastPoint = nil
            timer = Task { [weak self] in
                await self?.loadScreenshot()
                while !Task.isCancelled {
                    // Abstand bei jedem Durchlauf neu lesen – Änderungen in den Einstellungen gelten sofort
                    let interval = AppSettings.screenshotInterval
                    try? await Task.sleep(nanoseconds: UInt64(max(interval, 2)) * 1_000_000_000)
                    if interval > 0, !Task.isCancelled { await self?.loadScreenshot() }
                }
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        timer?.cancel()
        timer = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        if activeMode == .pointer { releaseCursor() }
        activeMode = nil
        screenshot = nil
        screenshotDate = nil
        // Auf dem Mac mini nichts gedrückt lassen
        queue.append(InputEvent(kind: .reset))
        flush()
    }

    // MARK: - Bildschirm anklicken

    func refreshScreenshot() {
        Task { await loadScreenshot() }
    }

    /// Ereignis aus der Bildansicht: Zeiger erst beim Klick an die Stelle setzen
    func handle(_ event: ScreenEvent) {
        guard activeMode == .screen else { return }
        switch event {
        case .down(let button, let clicks, let point):
            moveTo(point)
            enqueue(InputEvent(kind: .button, down: true, button: button, clicks: clicks))
        case .drag(let point):
            moveTo(point)
        case .up(let button, let clicks, let point):
            moveTo(point)
            enqueue(InputEvent(kind: .button, down: false, button: button, clicks: clicks))
            scheduleScreenshot(after: 0.8)
        case .scroll(let dx, let dy, let point, let ended):
            moveTo(point)
            enqueue(InputEvent(kind: .scroll, dx: dx, dy: dy))
            if ended { scheduleScreenshot(after: 0.8) }
        }
    }

    private func moveTo(_ point: CGPoint) {
        guard point != lastPoint else { return }
        lastPoint = point
        enqueue(InputEvent(kind: .moveTo, dx: Double(point.x), dy: Double(point.y)))
    }

    /// Neues Bildschirmfoto nach kurzer Pause (mehrere Klicks hintereinander → nur ein Foto)
    private func scheduleScreenshot(after seconds: Double) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.loadScreenshot()
        }
    }

    private func loadScreenshot() async {
        guard let client, !isLoadingScreenshot else { return }
        isLoadingScreenshot = true
        defer { isLoadingScreenshot = false }
        do {
            let data = try await client.screenshot()
            guard isActive, let image = NSImage(data: data) else { return }
            screenshot = image
            screenshotDate = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Ereignisse

    /// Gibt `true` zurück, wenn das Ereignis übertragen wurde und in der App nichts auslösen soll.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        switch event.type {
        case .keyDown:
            if event.keyCode == 53, event.modifierFlags.contains(.command) {   // ⌘⎋ beendet
                stop()
                return true
            }
            enqueue(InputEvent(kind: .key, code: event.keyCode, down: true, flags: flags))
        case .keyUp:
            enqueue(InputEvent(kind: .key, code: event.keyCode, down: false, flags: flags))
            if activeMode == .screen { scheduleScreenshot(after: 1.5) }
        case .flagsChanged:
            guard let modifier = Self.modifierForKey[event.keyCode] else { return true }
            let isDown = event.modifierFlags.contains(modifier)
            enqueue(InputEvent(kind: .key, code: event.keyCode, down: isDown, flags: flags))
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            enqueue(InputEvent(kind: .move, dx: Double(event.deltaX) * pointerSpeed,
                               dy: Double(event.deltaY) * pointerSpeed))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
            let button = event.type == .leftMouseDown || event.type == .leftMouseUp ? 0
                : event.type == .rightMouseDown || event.type == .rightMouseUp ? 1 : 2
            enqueue(InputEvent(kind: .button, down: down, button: button, clicks: event.clickCount))
        case .scrollWheel:
            // Mausrad liefert Zeilen, Trackpad Pixel
            let factor = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
            enqueue(InputEvent(kind: .scroll, dx: Double(event.scrollingDeltaX) * factor,
                               dy: Double(event.scrollingDeltaY) * factor))
        default:
            return false
        }
        return true   // Ereignis nicht in der App selbst verarbeiten
    }

    /// Bewegungen und Scrollen werden zusammengefasst, solange noch eine Anfrage unterwegs ist.
    private func enqueue(_ event: InputEvent) {
        var event = event
        if event.kind == .scroll, UserDefaults.standard.bool(forKey: AppSettings.invertScrollKey) {
            event.dx = event.dx.map { -$0 }
            event.dy = event.dy.map { -$0 }
        }
        if let last = queue.last, last.kind == event.kind, event.kind == .move || event.kind == .scroll {
            queue[queue.count - 1].dx = (last.dx ?? 0) + (event.dx ?? 0)
            queue[queue.count - 1].dy = (last.dy ?? 0) + (event.dy ?? 0)
        } else if let last = queue.last, last.kind == .moveTo, event.kind == .moveTo {
            // Beim Ziehen zählt nur die letzte Stelle
            queue[queue.count - 1] = event
        } else {
            queue.append(event)
        }
        flush()
    }

    private func flush() {
        guard !isSending, !queue.isEmpty, let client else { return }
        let batch = queue
        queue.removeAll()
        isSending = true
        Task {
            do {
                try await client.sendInput(batch)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "Übertragung fehlgeschlagen: \(error.localizedDescription)")
            }
            isSending = false
            flush()
        }
    }

    // MARK: - Mauszeiger festhalten (Modus "Zeiger steuern")

    private func captureCursor() {
        if let window = NSApp.keyWindow {
            window.acceptsMouseMovedEvents = true
            // Zeiger in die Fenstermitte setzen, damit Klicks nicht in anderen Apps landen
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            CGWarpMouseCursorPosition(CGPoint(x: window.frame.midX, y: primaryHeight - window.frame.midY))
        }
        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()
    }

    private func releaseCursor() {
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }
}

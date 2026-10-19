import Foundation
import ApplicationServices
import VoiceCore

/// Spielt Tastatur- und Mauseingaben vom MacBook auf dem Mac mini ab (Fernsteuer-Modus).
/// Als actor, damit die Ereignisse eines Pakets in der richtigen Reihenfolge ankommen.
actor RemoteInput {
    /// Gedrückte Maustasten (0 = links, 1 = rechts, 2 = andere) – für Ziehen und zum Loslassen beim Beenden.
    private var heldButtons: Set<Int> = []
    /// Tastencodes von ⌘ ⇧ ⌥ ⌃ (links und rechts)
    private static let modifierKeys: [CGKeyCode] = [55, 54, 56, 60, 58, 61, 59, 62]

    func apply(_ events: [InputEvent]) throws {
        guard AXIsProcessTrusted() else { throw Player.PermissionError() }
        Player.wakeDisplay()
        let source = CGEventSource(stateID: .hidSystemState)
        for event in events {
            switch event.kind {
            case .key: key(event, source: source)
            case .move: move(dx: event.dx ?? 0, dy: event.dy ?? 0, source: source)
            case .moveTo: moveTo(x: event.dx ?? 0.5, y: event.dy ?? 0.5, source: source)
            case .button: button(event, source: source)
            case .scroll: scroll(dx: event.dx ?? 0, dy: event.dy ?? 0, source: source)
            case .reset: reset(source: source)
            }
        }
    }

    private func key(_ event: InputEvent, source: CGEventSource?) {
        guard let code = event.code,
              let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: event.down ?? true)
        else { return }
        cgEvent.flags = CGEventFlags(rawValue: event.flags ?? 0)
        cgEvent.post(tap: .cghidEventTap)
    }

    /// Zeiger direkt an eine Stelle des Hauptbildschirms setzen (0…1), z. B. für Klicks im Bildschirmfoto
    private func moveTo(x: Double, y: Double, source: CGEventSource?) {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let target = CGPoint(x: bounds.minX + min(max(x, 0), 1) * (bounds.width - 1),
                             y: bounds.minY + min(max(y, 0), 1) * (bounds.height - 1))
        let current = CGEvent(source: nil)?.location ?? target
        post(to: target, dx: target.x - current.x, dy: target.y - current.y, source: source)
    }

    private func move(dx: Double, dy: Double, source: CGEventSource?) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let target = Self.clampToDisplays(CGPoint(x: current.x + dx, y: current.y + dy))
        post(to: target, dx: dx, dy: dy, source: source)
    }

    /// Bewegt den Zeiger (bzw. zieht, wenn eine Maustaste gedrückt ist)
    private func post(to target: CGPoint, dx: Double, dy: Double, source: CGEventSource?) {
        let type: CGEventType
        let mouseButton: CGMouseButton
        if heldButtons.contains(0) {
            (type, mouseButton) = (.leftMouseDragged, .left)
        } else if heldButtons.contains(1) {
            (type, mouseButton) = (.rightMouseDragged, .right)
        } else if heldButtons.contains(2) {
            (type, mouseButton) = (.otherMouseDragged, .center)
        } else {
            (type, mouseButton) = (.mouseMoved, .left)
        }
        let cgEvent = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target,
                              mouseButton: mouseButton)
        cgEvent?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        cgEvent?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        cgEvent?.post(tap: .cghidEventTap)
    }

    private func button(_ event: InputEvent, source: CGEventSource?) {
        let index = event.button ?? 0
        let down = event.down ?? true
        let types: (down: CGEventType, up: CGEventType, button: CGMouseButton)
        switch index {
        case 0: types = (.leftMouseDown, .leftMouseUp, .left)
        case 1: types = (.rightMouseDown, .rightMouseUp, .right)
        default: types = (.otherMouseDown, .otherMouseUp, .center)
        }
        if down { heldButtons.insert(index) } else { heldButtons.remove(index) }
        let location = CGEvent(source: nil)?.location ?? .zero
        let cgEvent = CGEvent(mouseEventSource: source, mouseType: down ? types.down : types.up,
                              mouseCursorPosition: location, mouseButton: types.button)
        cgEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(max(event.clicks ?? 1, 1)))
        cgEvent?.post(tap: .cghidEventTap)
    }

    private func scroll(dx: Double, dy: Double, source: CGEventSource?) {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private func reset(source: CGEventSource?) {
        for index in heldButtons.sorted() {
            button(InputEvent(kind: .button, down: false, button: index), source: source)
        }
        for code in Self.modifierKeys {
            let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            cgEvent?.flags = []
            cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Hält den Zeiger innerhalb der angeschlossenen Bildschirme.
    private static func clampToDisplays(_ point: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let area = displays.map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
        guard !area.isNull else { return point }
        return CGPoint(x: min(max(point.x, area.minX), area.maxX - 1),
                       y: min(max(point.y, area.minY), area.maxY - 1))
    }
}

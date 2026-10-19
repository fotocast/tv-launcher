import SwiftUI
import AppKit

/// Bildschirmfoto des Mac mini zum Anklicken (Modus "Bildschirm anklicken").
struct ScreenMirrorView: View {
    @EnvironmentObject private var forwarder: InputForwarder

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Label("Bildschirm des Mac mini", systemImage: "display")
                    .font(.headline)
                Spacer()
                if forwarder.isLoadingScreenshot {
                    ProgressView().controlSize(.small)
                }
                if let date = forwarder.screenshotDate {
                    Text("Stand \(date.formatted(date: .omitted, time: .standard))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    forwarder.refreshScreenshot()
                } label: {
                    Label("Neu laden", systemImage: "arrow.clockwise")
                }
                .disabled(forwarder.isLoadingScreenshot)
                .help("Sofort ein neues Bild vom Mac mini holen")
            }

            if let image = forwarder.screenshot {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .overlay { ClickCatcher { forwarder.handle($0) } }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15))
                    )
                    .opacity(forwarder.isLoadingScreenshot ? 0.85 : 1)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if forwarder.isLoadingScreenshot {
                            ProgressView("Hole Bild vom Mac mini …")
                        } else {
                            Image(systemName: "display")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            Text("Klicken, Doppelklicken, Rechtsklick (zwei Finger), Ziehen und Scrollen im Bild wirken an derselben Stelle am Mac mini. Das Bild wird nach jedem Klick und alle 60 Sekunden aktualisiert. Tasten gehen weiterhin an den Mac mini.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Unsichtbare Fläche über dem Bild, die Maus- und Trackpad-Ereignisse in Bildkoordinaten (0…1) meldet.
struct ClickCatcher: NSViewRepresentable {
    let onEvent: (InputForwarder.ScreenEvent) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onEvent = onEvent
    }

    final class CatcherView: NSView {
        var onEvent: ((InputForwarder.ScreenEvent) -> Void)?

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        private func point(_ event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil)
            guard bounds.width > 0, bounds.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
            return CGPoint(x: min(max(local.x / bounds.width, 0), 1),
                           y: min(max(local.y / bounds.height, 0), 1))
        }

        private static func button(_ event: NSEvent) -> Int {
            switch event.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return 0
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return 1
            default: return 2
            }
        }

        override func mouseDown(with event: NSEvent) {
            onEvent?(.down(button: Self.button(event), clicks: event.clickCount, at: point(event)))
        }
        override func mouseDragged(with event: NSEvent) { onEvent?(.drag(at: point(event))) }
        override func mouseUp(with event: NSEvent) {
            onEvent?(.up(button: Self.button(event), clicks: event.clickCount, at: point(event)))
        }
        override func rightMouseDown(with event: NSEvent) {
            onEvent?(.down(button: 1, clicks: event.clickCount, at: point(event)))
        }
        override func rightMouseDragged(with event: NSEvent) { onEvent?(.drag(at: point(event))) }
        override func rightMouseUp(with event: NSEvent) {
            onEvent?(.up(button: 1, clicks: event.clickCount, at: point(event)))
        }
        override func otherMouseDown(with event: NSEvent) {
            onEvent?(.down(button: 2, clicks: event.clickCount, at: point(event)))
        }
        override func otherMouseUp(with event: NSEvent) {
            onEvent?(.up(button: 2, clicks: event.clickCount, at: point(event)))
        }

        override func scrollWheel(with event: NSEvent) {
            // Mausrad liefert Zeilen, Trackpad Pixel
            let factor = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
            let ended = event.phase == .ended || event.momentumPhase == .ended
                || (event.phase.isEmpty && event.momentumPhase.isEmpty)
            onEvent?(.scroll(dx: Double(event.scrollingDeltaX) * factor,
                             dy: Double(event.scrollingDeltaY) * factor,
                             at: point(event), ended: ended))
        }
    }
}

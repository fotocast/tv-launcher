import SwiftUI
import AppKit
import VoiceCore

/// Zeile im Show-Editor: Art der Aktion (Taste / Doppelklick / keine) und ggf. die Taste.
struct KeyBindingRow: View {
    let title: String
    @Binding var binding: KeyBinding

    private var kind: Binding<KeyBinding.Kind> {
        Binding(
            get: { binding.kind },
            set: { newKind in
                switch newKind {
                case .key: if binding.kind != .key { binding = .space }
                case .doubleClick: binding = .doubleClick
                case .none: binding = .none
                }
            }
        )
    }

    var body: some View {
        LabeledContent(LocalizedStringKey(title)) {
            HStack(spacing: 8) {
                Picker(LocalizedStringKey(title), selection: kind) {
                    Text("Taste").tag(KeyBinding.Kind.key)
                    Text("Doppelklick Bildmitte").tag(KeyBinding.Kind.doubleClick)
                    Text("Nichts").tag(KeyBinding.Kind.none)
                }
                .labelsHidden()
                .fixedSize()
                if binding.kind == .key {
                    KeyRecorder(binding: $binding)
                }
            }
        }
    }
}

/// Knopf, der die nächste gedrückte Taste (mit ⌘⌥⇧⌃) aufnimmt.
struct KeyRecorder: View {
    @Binding var binding: KeyBinding
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? String(localized: "Taste drücken …") : L(binding.label))
                .font(.body.weight(.medium))
                .frame(minWidth: 120)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .help("Klicken und dann die Taste bzw. Tastenkombination drücken")
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            binding = Self.binding(from: event)
            stop()
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func binding(from event: NSEvent) -> KeyBinding {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        label += keyName(event)
        return .key(event.keyCode, label, modifiers: UInt64(flags.rawValue))
    }

    private static let names: [UInt16: String] = [
        49: "Leertaste", 36: "⏎", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Pos1", 119: "Ende", 116: "Bild↑", 121: "Bild↓",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        if let name = names[event.keyCode] { return name }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return characters.uppercased()
        }
        return "Taste \(event.keyCode)"
    }
}

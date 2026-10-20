import SwiftUI
import AppKit

/// Sofort abspielen: YouTube- oder Joyn-Filmlink einfügen → läuft am Fernseher.
/// Liegt ein passender Link in der Zwischenablage, wird er als Vorschlag angeboten.
struct InstantPlayField: View {
    @EnvironmentObject private var model: EpisodeModel
    @State private var text = ""
    @State private var clipboard: String?
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// Kompakt für die Seitenleiste
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(compact ? "YouTube- oder Joyn-Link" : "YouTube- oder Joyn-Filmlink einfügen", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { play(text) }
                Button {
                    play(text)
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || EpisodeModel.PlayableLink(text) == nil)
                .help("Am Fernseher abspielen")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if text.isEmpty, let clipboard, let link = EpisodeModel.PlayableLink(clipboard) {
                Button {
                    play(clipboard)
                } label: {
                    Label("\(link.label) aus der Zwischenablage abspielen", systemImage: "doc.on.clipboard")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .disabled(isWorking)
                .help(clipboard)
            }
        }
        .onAppear(perform: readClipboard)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            readClipboard()
        }
        .onChange(of: text) { _ in errorMessage = nil }
    }

    private func readClipboard() {
        clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func play(_ link: String) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await model.playLink(link)
                text = ""
                if link == clipboard { clipboard = nil }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

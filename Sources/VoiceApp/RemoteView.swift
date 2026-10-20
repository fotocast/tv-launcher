import SwiftUI
import VoiceCore

// MARK: - Runde Knöpfe

/// Großer runder Knopf im Stil der Apple-TV-Fernbedienung.
struct RoundButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background(
                Circle().fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            )
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Die Steuerknöpfe, in Leiste und Fernbedienung wiederverwendet.
struct TransportButtons: View {
    @EnvironmentObject private var model: EpisodeModel
    var size: CGFloat = 44
    var spacing: CGFloat = 14

    var body: some View {
        HStack(spacing: spacing) {
            button(.back, icon: "gobackward.10", help: "10 Sekunden zurück", scale: 1)
            button(.playPause, icon: "playpause.fill", help: "Pause oder weiter", scale: 1.25, prominent: true)
            button(.forward, icon: "goforward.10", help: "10 Sekunden vor", scale: 1)
            button(.fullscreen, icon: "arrow.up.left.and.arrow.down.right", help: "Vollbild an/aus", scale: 1)
            button(.subtitles, icon: "captions.bubble", help: subtitlesHelp, scale: 1)
                .disabled(!hasSubtitles)
            button(.closeTab, icon: "xmark.rectangle", help: "Browser-Tab am Mac mini schließen (⌘W)", scale: 1)
        }
    }

    /// Untertitel gehen nur, wenn die zuletzt gestartete Show eine Taste dafür hat (YouTube: C, Joyn: keine)
    private var hasSubtitles: Bool {
        (model.lastPlayedShow?.controls.subtitles.kind ?? .none) != .none
    }

    private var subtitlesHelp: String {
        guard let show = model.lastPlayedShow else { return String(localized: "Untertitel an/aus") }
        return hasSubtitles ? String(localized: "Untertitel an/aus (\(L(show.controls.subtitles.label)))")
            : String(localized: "Untertitel: für „\(show.displayName)“ gibt es keine Taste (z. B. Joyn) – einstellbar unter Einstellungen → Shows")
    }

    private func button(_ action: PlayerAction, icon: String, help: String,
                        scale: CGFloat, prominent: Bool = false) -> some View {
        Button {
            Task { await model.control(action) }
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(RoundButtonStyle(size: size * scale, prominent: prominent))
        .help(LocalizedStringKey(help))
    }
}

// MARK: - Player-Leiste unten

struct PlayerBar: View {
    @EnvironmentObject private var model: EpisodeModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                if let last = model.lastPlayed {
                    Text("\(model.show(last.show)?.displayName ?? "") · \(last.code)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(last.title)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text("Mac mini")
                        .font(.headline)
                }
            }
            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            TransportButtons(size: 40, spacing: 12)

            statusText
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var statusText: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .lineLimit(2)
        } else if let status = model.statusMessage {
            Label(status, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
                .lineLimit(2)
        }
    }
}

extension View {
    /// Hängt die Player-Leiste unten an.
    func playerBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { PlayerBar() }
    }
}

// MARK: - Fernbedienung

struct RemoteView: View {
    @EnvironmentObject private var model: EpisodeModel
    @EnvironmentObject private var forwarder: InputForwarder

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Video-Link abspielen", systemImage: "link")
                        .font(.headline)
                    InstantPlayField()
                        .controlSize(.large)
                }
                .padding(18)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

                nowPlaying

                TransportButtons(size: 76, spacing: 26)

                VolumeAndSleepBar()

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if let status = model.statusMessage {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                inputCard
            }
            .padding(32)
            // Im Bildschirm-Modus mehr Platz für das Bild des Mac mini
            .frame(maxWidth: forwarder.activeMode == .screen ? 1280 : 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Fernbedienung")
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if let last = model.lastPlayed {
            VStack(spacing: 4) {
                Text("ZULETZT GESTARTET · \((model.show(last.show)?.displayName ?? "").uppercased()) · \(last.code)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(last.title)
                    .font(.largeTitle.weight(.bold))
                if !last.subtitle.isEmpty {
                    Text(last.subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var modeDescription: String {
        switch (forwarder.mode, forwarder.isActive) {
        case (.pointer, true):
            return String(localized: "Aktiv: Alle Tasten, Zeigerbewegungen, Klicks und Scrollen gehen an den Mac mini. Beenden mit ⌘⎋.")
        case (.pointer, false):
            return String(localized: "Steuert den Mac mini, als säßest du davor. Der Mauszeiger wird hier ausgeblendet. Beenden mit ⌘⎋ oder durch Wechsel in eine andere App.")
        case (.screen, true):
            return String(localized: "Aktiv: Klicke im Bild unten auf eine Stelle – erst dann springt der Zeiger am Mac mini dorthin und klickt. Tasten werden übertragen. Beenden mit ⌘⎋.")
        case (.screen, false):
            return String(localized: "Zeigt ein Bild vom Bildschirm des Mac mini. Ein Klick ins Bild klickt an derselben Stelle – ohne dem verzögerten Zeiger zuzusehen.")
        }
    }

    private var inputCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: forwarder.mode == .screen ? "display" : (forwarder.isActive ? "keyboard.badge.ellipsis" : "keyboard"))
                    .font(.system(size: 30))
                    .foregroundStyle(forwarder.isActive ? Color.accentColor : .secondary)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac mini fernsteuern")
                        .font(.title3.weight(.semibold))
                    Text(modeDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Picker("Modus", selection: $forwarder.mode) {
                Label("Zeiger steuern", systemImage: "cursorarrow.motionlines").tag(InputForwarder.Mode.pointer)
                Label("Bildschirm anklicken", systemImage: "cursorarrow.rays").tag(InputForwarder.Mode.screen)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .disabled(forwarder.isActive)

            Button {
                forwarder.toggle()
            } label: {
                Label(forwarder.isActive ? "Übertragung beenden (⌘⎋)" : "Übertragung starten",
                      systemImage: forwarder.isActive ? "stop.fill" : "dot.radiowaves.left.and.right")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(forwarder.isActive ? .red : .accentColor)
            .controlSize(.large)

            if let error = forwarder.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if forwarder.activeMode == .screen {
                ScreenMirrorView()
            } else {
                Text("Gesten mit drei oder vier Fingern und ⌘⇥ bleiben beim MacBook. Zeigertempo unter Einstellungen (⌘,).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(forwarder.isActive ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: forwarder.isActive ? 2 : 1)
        )
    }
}

/// Lautstärke des Mac mini und Sleep-Timer (Fernbedienung)
struct VolumeAndSleepBar: View {
    @EnvironmentObject private var model: EpisodeModel
    private static let sleepChoices = [15, 30, 45, 60, 90, 120]

    var body: some View {
        HStack(spacing: 14) {
            Button { Task { await model.changeVolume("down") } } label: { Image(systemName: "speaker.minus.fill") }
                .buttonStyle(RoundButtonStyle(size: 44))
                .help("Leiser")
            Button { Task { await model.changeVolume("mute") } } label: {
                Image(systemName: model.volume?.muted == true ? "speaker.slash.fill" : "speaker.fill")
            }
            .buttonStyle(RoundButtonStyle(size: 44))
            .help("Ton aus/an")
            Button { Task { await model.changeVolume("up") } } label: { Image(systemName: "speaker.plus.fill") }
                .buttonStyle(RoundButtonStyle(size: 44))
                .help("Lauter")
            Text(model.volume.flatMap { v in v.volume.map { v.muted == true ? String(localized: "stumm") : "\($0) %" } } ?? "–")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Divider().frame(height: 28)

            Menu {
                ForEach(Self.sleepChoices, id: \.self) { minutes in
                    Button("In \(minutes) Minuten") { Task { await model.setSleepTimer(minutes: minutes) } }
                }
                if model.serverStatus?.sleepAt != nil {
                    Divider()
                    Button("Sleep-Timer aus") { Task { await model.setSleepTimer(minutes: 0) } }
                }
            } label: {
                if let end = model.serverStatus?.sleepAt {
                    Label("Bis \(end.formatted(date: .omitted, time: .shortened))", systemImage: "moon.zzz.fill")
                } else {
                    Label("Sleep-Timer", systemImage: "moon.zzz")
                }
            }
            .fixedSize()
            .help("Nach Ablauf pausieren und Display ausschalten")
        }
        .task { await model.loadServerInfo() }
    }
}

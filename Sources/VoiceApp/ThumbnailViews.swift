import SwiftUI
import VoiceCore

/// Löscht nach Rückfrage den Verlauf der einzeln gestarteten YouTube-Videos
struct ClearYouTubeHistoryButton: View {
    @EnvironmentObject private var model: EpisodeModel
    @State private var confirm = false

    var body: some View {
        Button {
            confirm = true
        } label: {
            Label("Verlauf löschen", systemImage: "trash")
        }
        .help("Alle zuletzt gestarteten YouTube-Videos aus der Liste entfernen")
        .confirmationDialog("YouTube-Verlauf löschen?", isPresented: $confirm) {
            Button("Verlauf löschen", role: .destructive) {
                Task { await model.clearYouTubeHistory() }
            }
        } message: {
            Text("Die Liste „YouTube-Videos“ wird geleert – in der App und in der Web-App. Kanäle bleiben erhalten.")
        }
    }
}

/// Vorschaubild im Format 16:9 (YouTube-Videos, Joyn-Filme), mit Platzhalter beim Laden.
struct Thumbnail: View {
    let url: String?
    var cornerRadius: CGFloat = 10
    /// Hochformat 9:16 (YouTube Shorts)
    var portrait = false

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(portrait ? 9 / 16 : 16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                    default:
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Raster mit großen Vorschaubildern – für YouTube-Kanäle und Filme
struct ThumbnailGridView: View {
    let title: String
    let episodes: [Episode]
    var emptyText = "Noch nichts vorhanden"
    /// Hochformat-Kacheln (Shorts)
    var portrait = false

    var body: some View {
        ScrollView {
            if episodes.isEmpty {
                Text(LocalizedStringKey(emptyText))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(40)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: portrait ? 150 : 250), spacing: 18)], spacing: 24) {
                ForEach(episodes, id: \.key) { ThumbnailCard(episode: $0) }
            }
            .padding(24)
        }
        .navigationTitle(title)
    }
}

struct ThumbnailCard: View {
    @EnvironmentObject private var model: EpisodeModel
    let episode: Episode
    @State private var isHovering = false

    var body: some View {
        Button {
            Task { await model.play(episode) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Thumbnail(url: episode.thumbnail, cornerRadius: 12, portrait: episode.isShort)
                    .overlay {
                        if model.isPlaying(episode) {
                            ProgressView().controlSize(.large)
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 52))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .opacity(isHovering ? 1 : 0)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if model.isLastPlayed(episode) {
                            Text("zuletzt")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }
                    .shadow(color: .black.opacity(isHovering ? 0.25 : 0.1), radius: isHovering ? 10 : 4, y: 3)
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)
                if !episode.subtitle.isEmpty {
                    Text(L(episode.subtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .scaleEffect(isHovering ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(model.isBusy)
        .help("Auf dem Mac mini abspielen")
    }
}

/// Kachel für eine ganze Show auf der Startseite (Joyn-Serie, YouTube-Kanal, eigene Show).
/// Ohne Bild: Farbverlauf mit Symbol. `avatar` = rundes Kanalbild unten links.
struct ShowCard: View {
    let title: String
    let subtitle: String
    let image: String?
    let icon: String
    var avatar: String? = nil
    var isRecent = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                artwork
                    .overlay(alignment: .bottomLeading) {
                        if let avatar {
                            AsyncImage(url: URL(string: avatar)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.secondary.opacity(0.3)
                            }
                            .frame(width: 46, height: 46)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                            .padding(10)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isRecent {
                            Text("Zuletzt gesehen")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                            .padding(10)
                            .opacity(isHovering ? 1 : 0)
                    }
                    .shadow(color: .black.opacity(isHovering ? 0.25 : 0.1), radius: isHovering ? 10 : 4, y: 3)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .scaleEffect(isHovering ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Öffnen")
    }

    @ViewBuilder
    private var artwork: some View {
        if image != nil {
            Thumbnail(url: image, cornerRadius: 12)
        } else {
            LinearGradient(colors: [Color(red: 0.55, green: 0.1, blue: 0.35), Color(red: 0.2, green: 0.1, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

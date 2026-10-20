import SwiftUI
import VoiceCore

/// Neuer Ordner in einem Schritt: Name eingeben und Shows ankreuzen.
struct NewFolderSheet: View {
    @EnvironmentObject private var model: EpisodeModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<String>
    @State private var isSaving = false

    /// - Parameter preselected: Shows, die schon angekreuzt sind (z. B. die gerade gewählte)
    init(preselected: Set<String> = []) {
        _selected = State(initialValue: preselected)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameExists: Bool { model.folders.contains(trimmedName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Neuer Ordner", systemImage: "folder.badge.plus")
                .font(.title2.weight(.semibold))
            TextField("Name des Ordners, z. B. Castingshows", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            if nameExists {
                Text("Diesen Ordner gibt es schon – die angekreuzten Shows kommen dazu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Welche Shows sollen hinein?")
                .font(.headline)
            List {
                ForEach(model.shows) { show in
                    Toggle(isOn: Binding(
                        get: { selected.contains(show.id) },
                        set: { if $0 { selected.insert(show.id) } else { selected.remove(show.id) } })) {
                        HStack {
                            Label(show.displayName, systemImage: ShowsSettingsView.kindIcon(show.kind))
                            Spacer()
                            if let folder = show.folder {
                                Label(folder, systemImage: "folder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 220)
            HStack {
                Text(selected.count == 1 ? String(localized: "1 Show ausgewählt")
                     : String(localized: "\(selected.count) Shows ausgewählt"))
                    .foregroundStyle(.secondary)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ordner anlegen", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || selected.isEmpty || isSaving)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
    }

    private func create() {
        guard !trimmedName.isEmpty, !selected.isEmpty else { return }
        isSaving = true
        let folder = trimmedName
        Task {
            // In der eigenen Reihenfolge nacheinander sichern
            for show in model.shows where selected.contains(show.id) && show.folder != folder {
                await model.setFolder(show.id, folder)
            }
            isSaving = false
            dismiss()
        }
    }
}

/// Menü „In Ordner legen“ für eine Show (vorhandene Ordner, neuer Ordner, herausnehmen)
struct MoveToFolderMenu: View {
    @EnvironmentObject private var model: EpisodeModel
    let show: Show
    let newFolder: () -> Void

    var body: some View {
        Menu("In Ordner legen") {
            ForEach(model.folders.filter { $0 != show.folder }, id: \.self) { folder in
                Button(folder) { Task { await model.setFolder(show.id, folder) } }
            }
            if model.folders.contains(where: { $0 != show.folder }) { Divider() }
            Button("Neuer Ordner …", action: newFolder)
        }
        if show.folder != nil {
            Button("Aus dem Ordner nehmen") { Task { await model.setFolder(show.id, nil) } }
        }
    }
}

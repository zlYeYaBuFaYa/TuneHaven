import SwiftUI

struct CreatePlaylistSheet: View {
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("歌单名称（必填）", text: $name)
                        .foregroundColor(palette.textPrimary)
                    TextField("简介（选填）", text: $description, axis: .vertical)
                        .lineLimit(3...5)
                        .foregroundColor(palette.textPrimary)
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(SemanticColor.danger)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("新建歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { createPlaylist() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        .foregroundColor(palette.primary)
                }
            }
        }
    }

    private func createPlaylist() {
        isLoading = true
        Task {
            do {
                _ = try await playlistService.createPlaylist(name: name, description: description.isEmpty ? nil : description)
                try? await Task.sleep(nanoseconds: 300_000_000)
                dismiss()
            } catch {
                AppLogger.shared.error(error, context: "创建歌单失败")
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct EditPlaylistSheet: View {
    let playlistId: UUID
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("歌单名称", text: $name)
                    TextField("简介（选填）", text: $description, axis: .vertical)
                        .lineLimit(3...5)
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(SemanticColor.danger)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("编辑歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            do {
                                try await playlistService.updatePlaylist(id: playlistId, name: name, description: description.isEmpty ? nil : description)
                                dismiss()
                            } catch {
                                AppLogger.shared.error(error, context: "编辑歌单失败")
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(palette.primary)
                }
            }
        }
        .task {
            guard !loaded else { return }
            if let playlist = playlistService.playlists.first(where: { $0.id == playlistId }) {
                name = playlist.name
                description = playlist.description ?? ""
            }
            loaded = true
        }
    }
}

struct AddToPlaylistSheet: View {
    let songIds: [UUID]
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId: UUID?

    private var userPlaylists: [Playlist] {
        playlistService.playlists.filter { !$0.isSystem }
    }

    var body: some View {
        NavigationStack {
            List(userPlaylists) { playlist in
                Button {
                    selectedId = playlist.id
                    Task {
                        do {
                            try await playlistService.addSongs(songIds, to: playlist.id)
                            dismiss()
                        } catch {
                            AppLogger.shared.error(error, context: "添加歌曲到歌单失败")
                            selectedId = nil
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        CoverImageView(path: playlist.coverImagePath, size: 44)
                        VStack(alignment: .leading) {
                            Text(playlist.name)
                                .foregroundColor(palette.textPrimary)
                            Text("\(playlist.songCount) 首")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                        Spacer()
                        if selectedId == playlist.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(palette.primary)
                        }
                    }
                }
                .listRowBackground(palette.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("添加到歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundColor(palette.primary)
                }
                // TODO: 考虑内嵌导航，创建歌单后自动将歌曲添加到新歌单，避免工作流中断
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        router.present(.createPlaylist)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(palette.primary)
                    }
                }
            }
        }
    }
}

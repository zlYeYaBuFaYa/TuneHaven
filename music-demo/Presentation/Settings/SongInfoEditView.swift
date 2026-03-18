import SwiftUI

struct SongInfoEditView: View {
    let songId: UUID

    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var song: Song?
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var isSaving = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Group {
                if let song {
                    Form {
                        Section("基本信息") {
                            labeledField("标题", text: $title)
                            labeledField("艺术家", text: $artist)
                            labeledField("专辑", text: $album)
                        }
                        .listRowBackground(palette.surface)

                        Section("文件信息") {
                            infoRow("格式", song.metadata.format.uppercased())
                            infoRow("时长", song.duration.formattedTime)
                            infoRow("大小", ByteCountFormatter.string(fromByteCount: song.fileSize, countStyle: .file))
                            infoRow("采样率", song.metadata.sampleRate.map { "\($0) Hz" } ?? "—")
                            infoRow("码率", song.metadata.bitRate.map { "\($0) kbps" } ?? "—")
                            infoRow("声道", song.metadata.channels.map { $0 == 1 ? "单声道" : "立体声" } ?? "—")
                            infoRow("添加时间", song.importDate.formatted(date: .abbreviated, time: .shortened))
                        }
                        .listRowBackground(palette.surface)
                    }
                    .scrollContentBackground(.hidden)
                    .adaptiveBackground()
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("歌曲信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(palette.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") { saveChanges() }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                            .foregroundColor(palette.primary)
                    }
                }
            }
        }
        .task { await loadSong() }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundColor(palette.textSecondary)
                .frame(width: 60, alignment: .leading)
            TextField(label, text: text)
                .foregroundColor(palette.textPrimary)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(palette.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadSong() async {
        let repo = CoreDataSongRepository()
        song = await repo.fetchSong(id: songId)
        if let s = song {
            title = s.title
            artist = s.artist
            album = s.album
        }
    }

    private func saveChanges() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        Task {
            try? await CoreDataStack.shared.performBackground { ctx in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", self.songId as CVarArg)
                request.fetchLimit = 1
                guard let entity = try ctx.fetch(request).first else { return }
                entity.title = self.title.trimmingCharacters(in: .whitespaces)
                entity.artist = self.artist.trimmingCharacters(in: .whitespaces)
                entity.album = self.album.trimmingCharacters(in: .whitespaces)
            }
            await libraryService.loadSongs()
            isSaving = false
            dismiss()
        }
    }
}

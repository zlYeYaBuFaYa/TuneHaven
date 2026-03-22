import SwiftUI

struct SongInfoEditView: View {
    let songId: UUID

    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var lyricsService: LyricsService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var song: Song?
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var isSaving = false
    @State private var saved = false
    @State private var showLyricsSearch = false
    @State private var showLyricsImporter = false
    @State private var showDeleteLyricsConfirm = false

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

                        lyricsSection(song)

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

    private func lyricsSection(_ song: Song) -> some View {
        Section("歌词") {
            infoRow("状态", lyricsStatusText(song))
            if song.lyricsSource != nil {
                infoRow("来源", lyricsSourceText(song))
            }

            Button {
                showLyricsSearch = true
            } label: {
                Label("搜索歌词", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundColor(palette.primary)
            }

            Button {
                showLyricsImporter = true
            } label: {
                Label("导入歌词", systemImage: "doc.text")
                    .font(.subheadline)
                    .foregroundColor(palette.primary)
            }

            if song.lyricsSource != nil || song.lyricsPath != nil {
                Button(role: .destructive) {
                    showDeleteLyricsConfirm = true
                } label: {
                    Label("删除歌词", systemImage: "trash")
                        .font(.subheadline)
                        .foregroundColor(SemanticColor.danger)
                }
            }
        }
        .listRowBackground(palette.surface)
        .sheet(isPresented: $showLyricsSearch) {
            if let song = self.song {
                LyricsSearchView(song: song) {
                    Task { await reloadSong() }
                }
                .environment(\.themePalette, palette)
            }
        }
        .fileImporter(
            isPresented: $showLyricsImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first,
                  let song = self.song else { return }
            Task {
                try? await lyricsService.importLyricsFile(url: url, for: song)
                await reloadSong()
            }
        }
        .alert("删除歌词", isPresented: $showDeleteLyricsConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard let song = self.song else { return }
                Task {
                    try? await lyricsService.deleteLyrics(for: song)
                    await reloadSong()
                }
            }
        } message: {
            Text("确定要删除当前歌曲的歌词吗？")
        }
    }

    private func lyricsStatusText(_ song: Song) -> String {
        switch song.lyricsSource {
        case .embedded: return "内嵌歌词"
        case .file: return "已有歌词（LRC 文件）"
        case .manual: return "手动导入歌词"
        case nil:
            let hasExternal = FileManager.default.fileExists(
                atPath: SandboxPathManager.lyricsFileURL(relativePath: "\(song.id.uuidString).lrc").path
            )
            return hasExternal ? "已有歌词（LRC 文件）" : "暂无歌词"
        }
    }

    private func lyricsSourceText(_ song: Song) -> String {
        switch song.lyricsSource {
        case .embedded: return "内嵌"
        case .file: return "本地文件"
        case .manual: return "手动导入"
        case nil: return "—"
        }
    }

    private func reloadSong() async {
        song = await libraryService.fetchSong(id: songId)
    }

    private func loadSong() async {
        await reloadSong()
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
            try? await libraryService.updateSongInfo(
                id: songId,
                title: title.trimmingCharacters(in: .whitespaces),
                artist: artist.trimmingCharacters(in: .whitespaces),
                album: album.trimmingCharacters(in: .whitespaces)
            )
            isSaving = false
            dismiss()
        }
    }
}

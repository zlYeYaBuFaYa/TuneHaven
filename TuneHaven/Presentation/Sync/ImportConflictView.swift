import SwiftUI

struct ImportConflictView: View {
    @EnvironmentObject private var syncImportService: SyncImportService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let analysisResult: SyncAnalysisResult
    let onComplete: (SyncImportResult) -> Void

    @State private var songConflicts: [SongConflict] = []
    @State private var playlistConflicts: [PlaylistConflict] = []
    @State private var globalSongResolution: SongConflictResolution?
    @State private var globalPlaylistResolution: PlaylistConflictResolution?
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !songConflicts.isEmpty {
                    songConflictSection
                }
                if !playlistConflicts.isEmpty {
                    playlistConflictSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("导入确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(palette.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始导入") { Task { await executeImport() } }
                        .foregroundColor(palette.primary)
                        .disabled(isImporting)
                }
            }
        }
        .onAppear {
            songConflicts = analysisResult.songConflicts
            playlistConflicts = analysisResult.playlistConflicts
        }
        .interactiveDismissDisabled(isImporting)
        .alert("导入失败", isPresented: $showErrorAlert) {
            Button("确定") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    // MARK: - 概览

    private var summarySection: some View {
        Section {
            infoRow("来源设备", value: analysisResult.manifest.deviceName)
            if analysisResult.newSongsCount > 0 {
                infoRow("新歌曲", value: "\(analysisResult.newSongsCount) 首")
            }
            if analysisResult.newPlaylistsCount > 0 {
                infoRow("新歌单", value: "\(analysisResult.newPlaylistsCount) 个")
            }
            if !songConflicts.isEmpty {
                infoRow("歌曲冲突", value: "\(songConflicts.count) 首")
            }
            if !playlistConflicts.isEmpty {
                infoRow("歌单冲突", value: "\(playlistConflicts.count) 个")
            }
        } header: {
            Text("概览")
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - 歌曲冲突

    private var songConflictSection: some View {
        Section {
            globalSongResolutionPicker

            ForEach(Array(songConflicts.enumerated()), id: \.element.id) { index, conflict in
                VStack(alignment: .leading, spacing: 6) {
                    Text(conflict.incoming.title)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text("\(conflict.incoming.artist) · \(conflict.incoming.album)")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    if globalSongResolution == nil {
                        Picker("处理方式", selection: songResolutionBinding(for: index)) {
                            Text("跳过").tag(SongConflictResolution.skip)
                            Text("替换").tag(SongConflictResolution.replace)
                            Text("另存副本").tag(SongConflictResolution.saveAsCopy)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("歌曲冲突")
                .foregroundColor(palette.textSecondary)
        }
    }

    private var globalSongResolutionPicker: some View {
        HStack {
            Text("应用到全部")
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Menu {
                Button("逐个处理") { globalSongResolution = nil }
                Button("全部跳过") { globalSongResolution = .skip }
                Button("全部替换") { globalSongResolution = .replace }
                Button("全部另存副本") { globalSongResolution = .saveAsCopy }
            } label: {
                HStack(spacing: 4) {
                    Text(globalSongResolutionLabel)
                        .font(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(palette.primary)
            }
        }
    }

    private var globalSongResolutionLabel: String {
        switch globalSongResolution {
        case .skip: return "全部跳过"
        case .replace: return "全部替换"
        case .saveAsCopy: return "全部另存"
        case nil: return "逐个处理"
        }
    }

    // MARK: - 歌单冲突

    private var playlistConflictSection: some View {
        Section {
            globalPlaylistResolutionPicker

            ForEach(Array(playlistConflicts.enumerated()), id: \.element.id) { index, conflict in
                VStack(alignment: .leading, spacing: 6) {
                    Text(conflict.incoming.name)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text("本地已存在同名歌单（\(conflict.existing.songCount) 首）")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    if globalPlaylistResolution == nil {
                        Picker("处理方式", selection: playlistResolutionBinding(for: index)) {
                            Text("合并").tag(PlaylistConflictResolution.merge)
                            Text("替换").tag(PlaylistConflictResolution.replace)
                            Text("新建副本").tag(PlaylistConflictResolution.createCopy)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("歌单冲突")
                .foregroundColor(palette.textSecondary)
        }
    }

    private var globalPlaylistResolutionPicker: some View {
        HStack {
            Text("应用到全部")
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Menu {
                Button("逐个处理") { globalPlaylistResolution = nil }
                Button("全部合并") { globalPlaylistResolution = .merge }
                Button("全部替换") { globalPlaylistResolution = .replace }
                Button("全部新建副本") { globalPlaylistResolution = .createCopy }
            } label: {
                HStack(spacing: 4) {
                    Text(globalPlaylistResolutionLabel)
                        .font(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(palette.primary)
            }
        }
    }

    private var globalPlaylistResolutionLabel: String {
        switch globalPlaylistResolution {
        case .merge: return "全部合并"
        case .replace: return "全部替换"
        case .createCopy: return "全部新建"
        case nil: return "逐个处理"
        }
    }

    // MARK: - Bindings

    private func songResolutionBinding(for index: Int) -> Binding<SongConflictResolution> {
        Binding(
            get: { songConflicts[index].resolution ?? .skip },
            set: { songConflicts[index].resolution = $0 }
        )
    }

    private func playlistResolutionBinding(for index: Int) -> Binding<PlaylistConflictResolution> {
        Binding(
            get: { playlistConflicts[index].resolution ?? .merge },
            set: { playlistConflicts[index].resolution = $0 }
        )
    }

    // MARK: - Actions

    private func executeImport() async {
        isImporting = true

        syncImportService.songConflicts = songConflicts
        syncImportService.playlistConflicts = playlistConflicts

        do {
            let result = try await syncImportService.executeImport(
                analysisResult: analysisResult,
                songResolution: globalSongResolution,
                playlistResolution: globalPlaylistResolution
            )
            onComplete(result)
        } catch {
            AppLogger.shared.error(error, context: "ImportConflictView 导入执行失败")
            errorMessage = error.localizedDescription
            showErrorAlert = true
            isImporting = false
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct BackupCenterView: View {
    let presentation: BackupPresentation

    @EnvironmentObject private var backupService: BackupRestoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @State private var includeAudio = true
    @State private var estimateText = "计算中..."
    @State private var estimateTooLarge = false
    @State private var mode: BackupRestoreMode = .merge
    @State private var songChoice: BackupSongConflictChoice = .skip
    @State private var playlistChoice: BackupPlaylistConflictChoice = .merge
    @State private var applySongsToAll = true
    @State private var applyPlaylistsToAll = true
    @State private var songOverrides: [UUID: BackupSongConflictChoice] = [:]
    @State private var playlistOverrides: [UUID: BackupPlaylistConflictChoice] = [:]
    @State private var preview: BackupPreview?
    @State private var packageURL: URL?
    @State private var showImporter = false
    @State private var confirmReplace = false
    @State private var shareURL: URL?
    @State private var summary: BackupRestoreSummary?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                if presentation.kind == .export {
                    exportForm
                } else {
                    restoreForm
                }
                if let progress = backupService.progress {
                    Section("进度") {
                        ProgressView(value: progress.fraction) {
                            Text(progress.phase)
                        }
                        Button("取消", role: .cancel) {
                            backupService.cancel()
                        }
                        .disabled(!backupService.isBusy)
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .navigationTitle(presentation.kind == .export ? "导出备份" : "从备份恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task(id: includeAudio) {
            guard presentation.kind == .export else { return }
            let bytes = await backupService.estimate(includeAudio: includeAudio)
            estimateText = BackupByteCount.format(bytes)
            estimateTooLarge = includeAudio && bytes > 3_500_000_000
        }
        .task {
            if let url = presentation.packageURL {
                packageURL = url
                await loadPreview(url)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [Self.backupType],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                packageURL = url
                Task { await loadPreview(url) }
            }
        }
        .confirmationDialog("替换曲库？", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("清空并恢复", role: .destructive) {
                Task { await runRestore() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清空本地自建曲库和自建歌单后再导入。此操作不可撤销，除非你另有旧备份。系统歌单「我喜欢」按备份中的收藏标记重建；「最近播放」不会从备份恢复。若备份不含音频，曲目会显示为「未找到」。订阅状态不会改变。")
        }
    }

    private var exportForm: some View {
        Group {
            Section {
                Toggle("包含音频", isOn: $includeAudio)
                LabeledContent("预估体积", value: estimateText)
                if estimateTooLarge {
                    Text("体积接近 4GB 上限。可以关闭「包含音频」，只导出元数据。")
                        .font(.footnote)
                        .foregroundColor(palette.textSecondary)
                }
            } footer: {
                Text("不含播放次数、搜索历史、WebDAV 账号和订阅状态。")
            }
            Section {
                Button(backupService.isBusy ? "正在导出..." : "生成备份包") {
                    Task { await runExport() }
                }
                .disabled(backupService.isBusy)
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("分享到文件 App", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var restoreForm: some View {
        Section {
            Button("选择 .tunehaven 备份包") { showImporter = true }
            if let preview {
                LabeledContent("歌曲", value: "\(preview.manifest.songCount)")
                LabeledContent("歌单", value: "\(preview.manifest.playlistCount)")
                LabeledContent("体积", value: BackupByteCount.format(preview.manifest.payloadBytes))
                LabeledContent("音频", value: preview.manifest.includesAudio ? "包含" : "仅元数据")
                LabeledContent("导出版本", value: preview.manifest.appVersion)
            }
        }
        if preview != nil {
            Section("恢复方式") {
                Picker("模式", selection: $mode) {
                    ForEach(BackupRestoreMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Text(mode.detail)
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
            }
            if mode == .merge {
                conflictSection
            }
            if let summary {
                Section("结果") {
                    LabeledContent("成功", value: "\(summary.songsSucceeded)")
                    LabeledContent("跳过", value: "\(summary.songsSkipped + summary.playlistsSkipped)")
                    LabeledContent("缺失音频", value: "\(summary.songsMissingAudio)")
                    if summary.preferencesRestored {
                        Text("主题和播放偏好已恢复")
                            .font(.footnote)
                    }
                }
            }
            Section {
                Button(backupService.isBusy ? "正在恢复..." : "开始恢复") {
                    if mode == .replaceLibrary {
                        confirmReplace = true
                    } else {
                        Task { await runRestore() }
                    }
                }
                .disabled(backupService.isBusy || packageURL == nil)
            }
        }
    }

    @ViewBuilder
    private var conflictSection: some View {
        Section("歌曲冲突") {
            Picker("处理方式", selection: $songChoice) {
                ForEach(BackupSongConflictChoice.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            Toggle("应用到全部歌曲", isOn: $applySongsToAll)
            if !applySongsToAll, let conflicts = preview?.songConflicts, conflicts.isEmpty == false {
                ForEach(conflicts) { conflict in
                    Picker(conflict.title, selection: songOverrideBinding(conflict.id)) {
                        ForEach(BackupSongConflictChoice.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }
            } else if preview?.songConflicts.isEmpty == false {
                Text("\(preview?.songConflicts.count ?? 0) 首与本地重名")
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
            }
        }
        Section("歌单冲突") {
            Picker("处理方式", selection: $playlistChoice) {
                ForEach(BackupPlaylistConflictChoice.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            Toggle("应用到全部歌单", isOn: $applyPlaylistsToAll)
            if !applyPlaylistsToAll, let conflicts = preview?.playlistConflicts, conflicts.isEmpty == false {
                ForEach(conflicts) { conflict in
                    Picker(conflict.title, selection: playlistOverrideBinding(conflict.id)) {
                        ForEach(BackupPlaylistConflictChoice.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }
            }
        }
    }

    private func songOverrideBinding(_ id: UUID) -> Binding<BackupSongConflictChoice> {
        Binding(
            get: { songOverrides[id] ?? songChoice },
            set: { songOverrides[id] = $0 }
        )
    }

    private func playlistOverrideBinding(_ id: UUID) -> Binding<BackupPlaylistConflictChoice> {
        Binding(
            get: { playlistOverrides[id] ?? playlistChoice },
            set: { playlistOverrides[id] = $0 }
        )
    }

    private func runExport() async {
        errorText = nil
        do {
            shareURL = try await backupService.export(includeAudio: includeAudio)
        } catch {
            errorText = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadPreview(_ url: URL) async {
        errorText = nil
        do {
            preview = try await backupService.inspect(url: url)
        } catch {
            preview = nil
            errorText = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runRestore() async {
        guard let packageURL else { return }
        errorText = nil
        let resolution = BackupConflictResolution(
            songChoice: songChoice,
            playlistChoice: playlistChoice,
            applySongChoiceToAll: applySongsToAll,
            applyPlaylistChoiceToAll: applyPlaylistsToAll,
            songOverrides: songOverrides,
            playlistOverrides: playlistOverrides
        )
        do {
            summary = try await backupService.restore(url: packageURL, mode: mode, resolution: resolution)
        } catch {
            errorText = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static var backupType: UTType {
        UTType(BackupPackageFormat.typeIdentifier)
            ?? UTType(filenameExtension: BackupPackageFormat.fileExtension)
            ?? .data
    }
}

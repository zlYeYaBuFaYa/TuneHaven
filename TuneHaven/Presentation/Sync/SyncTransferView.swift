import SwiftUI

struct SyncTransferView: View {
    @EnvironmentObject private var syncExportService: SyncExportService
    @EnvironmentObject private var syncImportService: SyncImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var activeSheet: SyncSheet?
    @State private var showExportSongSelector = false
    @State private var showExportPlaylistSelector = false
    @State private var showFileImporter = false
    @State private var importResult: SyncImportResult?
    @State private var showResultAlert = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    enum SyncSheet: Identifiable {
        case importAnalysis(SyncAnalysisResult)
        var id: String {
            switch self {
            case .importAnalysis: return "importAnalysis"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                exportSection
                importSection
                if syncExportService.isExporting || syncImportService.isImporting {
                    progressSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("同步与传输")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.primary)
                }
            }
        }
        .sheet(isPresented: $showExportSongSelector) {
            ExportSongSelectorView()
                .environment(\.themePalette, palette)
                .environmentObject(syncExportService)
                .environmentObject(libraryService)
        }
        .sheet(isPresented: $showExportPlaylistSelector) {
            ExportPlaylistSelectorView()
                .environment(\.themePalette, palette)
                .environmentObject(syncExportService)
                .environmentObject(playlistService)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .importAnalysis(let result):
                ImportConflictView(analysisResult: result) { importResult in
                    self.importResult = importResult
                    self.showResultAlert = true
                    self.activeSheet = nil
                }
                .environment(\.themePalette, palette)
                .environmentObject(syncImportService)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await handleImportFile(url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
        .alert("导入完成", isPresented: $showResultAlert) {
            Button("确定") {}
        } message: {
            if let r = importResult {
                Text(importResultMessage(r))
            }
        }
        .alert("错误", isPresented: $showErrorAlert) {
            Button("确定") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    // MARK: - Sections

    private var exportSection: some View {
        Section {
            actionRow(icon: "music.note.list", title: "导出歌曲", subtitle: "选择歌曲导出为 .tunehaven 文件") {
                showExportSongSelector = true
            }
            actionRow(icon: "list.bullet.rectangle", title: "导出歌单", subtitle: "导出歌单结构，可选包含音频文件") {
                showExportPlaylistSelector = true
            }
        } header: {
            Label("导出", systemImage: "square.and.arrow.up")
                .foregroundColor(palette.textSecondary)
        }
    }

    private var importSection: some View {
        Section {
            actionRow(icon: "doc.badge.plus", title: "导入 .tunehaven 文件", subtitle: "从文件中导入歌曲和歌单") {
                showFileImporter = true
            }
        } header: {
            Label("导入", systemImage: "square.and.arrow.down")
                .foregroundColor(palette.textSecondary)
        }
    }

    private var progressSection: some View {
        Section {
            if let progress = syncExportService.progress ?? syncImportService.progress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(phaseLabel(progress.phase))
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                        Spacer()
                        Text("\(progress.current)/\(progress.total)")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                    ProgressView(value: progress.fractionCompleted)
                        .tint(palette.primary)
                    if let fileName = progress.currentFileName {
                        Text(fileName)
                            .font(.caption2)
                            .foregroundColor(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("进度")
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - Helpers

    private func actionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(palette.primary)
            }
        }
    }

    private func handleImportFile(_ url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard url.pathExtension.lowercased() == "tunehaven" else {
            errorMessage = "请选择 .tunehaven 格式的文件"
            showErrorAlert = true
            return
        }

        do {
            let result = try await syncImportService.analyze(fileURL: url)
            if result.songConflicts.isEmpty && result.playlistConflicts.isEmpty {
                let importResult = try await syncImportService.executeImport(
                    analysisResult: result,
                    songResolution: nil,
                    playlistResolution: nil
                )
                self.importResult = importResult
                self.showResultAlert = true
                await libraryService.loadSongs()
            } else {
                activeSheet = .importAnalysis(result)
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func phaseLabel(_ phase: SyncPhase) -> String {
        switch phase {
        case .preparing: return "准备中..."
        case .exporting: return "导出中..."
        case .transferring: return "传输中..."
        case .importing: return "导入中..."
        case .matching: return "匹配中..."
        case .completed: return "完成"
        case .failed(let msg): return "失败: \(msg)"
        }
    }

    private func importResultMessage(_ r: SyncImportResult) -> String {
        var parts: [String] = []
        if r.songsImported > 0 { parts.append("导入 \(r.songsImported) 首歌曲") }
        if r.playlistsImported > 0 { parts.append("导入 \(r.playlistsImported) 个歌单") }
        if r.songsSkipped > 0 { parts.append("跳过 \(r.songsSkipped) 首") }
        if r.missingSongsCount > 0 { parts.append("\(r.missingSongsCount) 首歌曲待匹配") }
        if r.songsFailed > 0 { parts.append("\(r.songsFailed) 首失败") }
        return parts.isEmpty ? "无变更" : parts.joined(separator: "\n")
    }
}

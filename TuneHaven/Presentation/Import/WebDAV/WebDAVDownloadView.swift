import SwiftUI

struct WebDAVDownloadView: View {
    @EnvironmentObject private var webDAVService: WebDAVService
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let files: [WebDAVFile]
    let account: WebDAVAccount
    var onComplete: () -> Void = {}

    @State private var result: WebDAVImportResult?
    @State private var isProcessing = true

    var body: some View {
        NavigationStack {
            List {
                if isProcessing {
                    progressSection
                    taskListSection
                } else if let result {
                    resultSection(result)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("下载与导入")
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isProcessing {
                        Button("取消") {
                            webDAVService.cancelDownload()
                        }
                        .foregroundColor(SemanticColor.danger)
                    }
                }
                if !isProcessing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            onComplete()
                            dismiss()
                        }
                        .foregroundColor(palette.primary)
                    }
                }
            }
            .task { await startDownload() }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("整体进度")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                    let completed = webDAVService.downloadTasks.filter {
                        if case .completed = $0.status { return true }
                        if case .failed = $0.status { return true }
                        if case .skippedOversize = $0.status { return true }
                        return false
                    }.count
                    Text("\(completed)/\(files.count)")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                ProgressView(value: webDAVService.overallProgress)
                    .tint(palette.primary)
            }
            .padding(.vertical, 4)
            .listRowBackground(palette.surface)
        }
    }

    private var taskListSection: some View {
        Section {
            ForEach(webDAVService.downloadTasks) { task in
                taskRow(task)
            }
        }
    }

    private func taskRow(_ task: WebDAVDownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusIcon(task.status)
                Text(task.file.fileName)
                    .font(.subheadline)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(task.file.formattedSize)
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }

            if case .downloading = task.status {
                ProgressView(value: task.progress)
                    .tint(palette.primary)
            }

            if let error = task.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(SemanticColor.danger)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private func statusIcon(_ status: WebDAVDownloadTask.DownloadStatus) -> some View {
        switch status {
        case .waiting:
            Image(systemName: "clock")
                .foregroundColor(palette.textTertiary)
                .font(.caption)
        case .downloading:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(SemanticColor.success)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(SemanticColor.danger)
                .font(.caption)
        case .skippedOversize:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(SemanticColor.warning)
                .font(.caption)
        }
    }

    // MARK: - Result

    private func resultSection(_ result: WebDAVImportResult) -> some View {
        Section("导入结果") {
            if let importResult = result.importResult {
                resultRow("成功导入", count: importResult.successCount,
                          color: palette.primary, icon: "checkmark.circle")
                if importResult.skippedDuplicateCount > 0 {
                    resultRow("已跳过（重复）", count: importResult.skippedDuplicateCount,
                              color: palette.textSecondary, icon: "arrow.2.circlepath")
                }
                if importResult.failedCount > 0 {
                    resultRow("导入失败", count: importResult.failedCount,
                              color: SemanticColor.danger, icon: "xmark.circle")
                }
            }
            if result.downloadFailedCount > 0 {
                resultRow("下载失败", count: result.downloadFailedCount,
                          color: SemanticColor.danger, icon: "icloud.slash")
            }
            if result.skippedOversizeCount > 0 {
                resultRow("文件过大（已跳过）", count: result.skippedOversizeCount,
                          color: SemanticColor.warning, icon: "exclamationmark.triangle")
            }
        }
    }

    private func resultRow(_ title: String, count: Int, color: Color, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Text("\(count) 首")
                .font(.subheadline.bold())
                .foregroundColor(color)
        }
        .listRowBackground(palette.surface)
    }

    // MARK: - Logic

    private func startDownload() async {
        result = await webDAVService.downloadAndImport(
            files: files
        ) { _ in }

        await libraryService.loadSongs()
        isProcessing = false
    }
}

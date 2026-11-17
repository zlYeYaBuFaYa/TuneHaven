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
    @State private var isCancelling = false

    var body: some View {
        NavigationStack {
            List {
                if isProcessing {
                    progressSection
                    taskListSection
                } else if let result {
                    if let imported = result.importResult {
                        ImportResultSection(result: imported, wasCancelled: isCancelling)
                    }
                    if isCancelling || result.downloadFailedCount > 0 || result.skippedOversizeCount > 0 || !result.errors.isEmpty {
                        resultSection(result)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("下载与导入")
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isProcessing {
                        Button(isCancelling ? "正在停止…" : "停止下载") {
                            isCancelling = true
                            webDAVService.cancelDownload()
                        }
                        .foregroundColor(palette.accent)
                        .disabled(isCancelling || webDAVService.overallProgress >= 1)
                    }
                }
                if !isProcessing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            onComplete()
                            dismiss()
                        }
                        .foregroundColor(palette.accent)
                    }
                }
            }
            .task { await startDownload() }
        }
        .interactiveDismissDisabled(isProcessing)
    }

    // MARK: - Progress

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(webDAVService.overallProgress >= 1 && importService.isImporting ? "正在保存到音乐库" : "下载进度")
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
                    .tint(palette.accent)
            }
            .padding(.vertical, 4)
            .importRowSurface()
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
                    .foregroundColor(palette.textSecondary)
            }

            if case .downloading = task.status {
                ProgressView(value: task.progress)
                    .tint(palette.accent)
            }

            if let error = task.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(SemanticColor.danger)
            }
        }
        .padding(.vertical, 2)
        .importRowSurface()
    }

    @ViewBuilder
    private func statusIcon(_ status: WebDAVDownloadTask.DownloadStatus) -> some View {
        switch status {
        case .waiting:
            Image(systemName: "clock")
                .foregroundColor(palette.textSecondary)
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
        Section("下载结果") {
            if isCancelling {
                Label("已停止，已导入的音乐会保留", systemImage: "stop.circle")
                    .foregroundColor(palette.textPrimary).importRowSurface()
            }
            if result.downloadFailedCount > 0 {
                resultRow("下载失败", count: result.downloadFailedCount,
                          color: SemanticColor.danger, icon: "icloud.slash")
            }
            if result.skippedOversizeCount > 0 {
                resultRow("文件过大（已跳过）", count: result.skippedOversizeCount,
                          color: SemanticColor.warning, icon: "exclamationmark.triangle")
            }
            ForEach(Array(result.errors.filter { $0 != "已取消" }.enumerated()), id: \.offset) { _, message in
                Text(message).font(.footnote).foregroundColor(palette.textSecondary).importRowSurface()
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
        .importRowSurface()
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

import SwiftUI
import UniformTypeIdentifiers

struct ImportFilesView: View {
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var showDocumentPicker = false
    @State private var showWifiTransfer = false
    @State private var showAppleMusicImport = false
    @State private var showCloudDriveImport = false
    @State private var importResult: ImportResult?
    @State private var isImporting = false
    @State private var progress: ImportProgress?
    @State private var filePickerError: String?
    @State private var showResultAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("从文件导入")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(palette.textPrimary)
                                Text("支持 MP3, M4A, AAC, WAV, FLAC, ALAC, AIFF, CAF，单文件不超过 500MB")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "folder")
                                .foregroundColor(palette.primary)
                        }
                    }
                    .listRowBackground(palette.surface)

                    Button {
                        showAppleMusicImport = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("从 Apple Music 资料库导入")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(palette.textPrimary)
                                Text("扫描并导入设备上已下载的本地音乐文件")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "music.note.house")
                                .foregroundColor(palette.primary)
                        }
                    }
                    .listRowBackground(palette.surface)

                    Button {
                        showCloudDriveImport = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("云盘导入")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(palette.textPrimary)
                                Text("从百度网盘等云盘服务导入音乐文件")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "cloud")
                                .foregroundColor(palette.primary)
                        }
                    }
                    .listRowBackground(palette.surface)

                    Button {
                        showWifiTransfer = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("WiFi 传输")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(palette.textPrimary)
                                Text("通过浏览器从电脑无线传输音乐")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "wifi")
                                .foregroundColor(palette.primary)
                        }
                    }
                    .listRowBackground(palette.surface)
                } header: {
                    Text("导入方式")
                        .foregroundColor(palette.textSecondary)
                }

                if isImporting, let p = progress {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("正在导入 \(p.currentFileName)")
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)
                                .lineLimit(1)
                            ProgressView(value: p.percentage)
                                .tint(palette.primary)
                            HStack {
                                Text("\(p.completedCount)/\(p.totalCount)")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                                if let remaining = p.estimatedRemainingSeconds {
                                    Text("约剩 \(remaining.formattedTime)")
                                        .font(.caption)
                                        .foregroundColor(palette.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(palette.surface)

                        Button("取消导入") {
                            importService.cancelImport()
                        }
                        .foregroundColor(SemanticColor.danger)
                        .listRowBackground(palette.surface)
                    }
                }

                if let error = filePickerError {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(SemanticColor.warning)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("导入音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.primary)
                }
            }
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: UTType.allSupportedAudio,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                filePickerError = nil
                startImport(urls: urls)
            case .failure(let error):
                AppLogger.shared.error("[ImportFiles] fileImporter failure: \(error.localizedDescription)")
                filePickerError = "文件选择失败：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showWifiTransfer) {
            WiFiTransferView()
                .environment(\.themePalette, palette)
                .environmentObject(importService)
                .environmentObject(libraryService)
        }
        .sheet(isPresented: $showAppleMusicImport) {
            AppleMusicImportView()
                .environment(\.themePalette, palette)
                .environmentObject(importService)
                .environmentObject(libraryService)
        }
        .sheet(isPresented: $showCloudDriveImport) {
            CloudDriveImportView()
                .environment(\.themePalette, palette)
                .environmentObject(importService)
                .environmentObject(libraryService)
        }
        .alert(resultAlertTitle, isPresented: $showResultAlert) {
            Button("好的") {}
        } message: {
            if let result = importResult {
                Text(resultAlertMessage(result))
            }
        }
    }

    private func startImport(urls: [URL]) {
        isImporting = true
        importResult = nil
        Task {
            let result = await importService.importFromFiles(urls: urls) { p in
                progress = p
            }
            isImporting = false
            importResult = result
            showResultAlert = true
            await libraryService.loadSongs()
        }
    }

    private var resultAlertTitle: String {
        guard let result = importResult else { return "导入完成" }
        if result.failedCount > 0 && result.successCount == 0 { return "导入失败" }
        if result.successCount > 0 { return "导入成功" }
        return "导入完成"
    }

    private func resultAlertMessage(_ result: ImportResult) -> String {
        var parts: [String] = []
        if result.successCount > 0 {
            parts.append("成功导入 \(result.successCount) 首")
        }
        if result.skippedDuplicateCount > 0 {
            parts.append("跳过重复 \(result.skippedDuplicateCount) 首")
        }
        if result.skippedFormatCount > 0 {
            parts.append("格式不支持 \(result.skippedFormatCount) 首")
        }
        if result.skippedOversizeCount > 0 {
            parts.append("超过大小限制 \(result.skippedOversizeCount) 首")
        }
        if result.failedCount > 0 {
            parts.append("失败 \(result.failedCount) 首")
        }
        if result.incompleteMetadataCount > 0 {
            parts.append("其中 \(result.incompleteMetadataCount) 首元数据不完整")
        }
        return parts.isEmpty ? "没有可导入的文件" : parts.joined(separator: "，")
    }

}

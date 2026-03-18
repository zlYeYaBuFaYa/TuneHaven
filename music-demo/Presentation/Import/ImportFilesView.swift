import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    static let mp3 = UTType(filenameExtension: "mp3") ?? .audio
    static let alac = UTType(filenameExtension: "alac") ?? .audio
    static let flac = UTType(filenameExtension: "flac") ?? .audio
}

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
                                Text("支持 MP3, M4A, AAC, WAV, ALAC，单文件不超过 500MB")
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

                if let result = importResult {
                    importResultSection(result)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
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
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                startImport(urls: urls)
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
            await libraryService.loadSongs()
        }
    }

    @ViewBuilder
    private func importResultSection(_ result: ImportResult) -> some View {
        Section("导入结果") {
            resultRow("成功", count: result.successCount, color: palette.primary, icon: "checkmark.circle")
            if result.incompleteMetadataCount > 0 {
                resultRow("元数据不完整", count: result.incompleteMetadataCount, color: SemanticColor.warning, icon: "exclamationmark.circle")
            }
            if result.skippedDuplicateCount > 0 {
                resultRow("已跳过（重复）", count: result.skippedDuplicateCount, color: palette.textSecondary, icon: "arrow.2.circlepath")
            }
            if result.skippedFormatCount > 0 {
                resultRow("格式不支持", count: result.skippedFormatCount, color: palette.textTertiary, icon: "doc.badge.minus")
            }
            if result.skippedOversizeCount > 0 {
                resultRow("超过大小限制", count: result.skippedOversizeCount, color: SemanticColor.warning, icon: "exclamationmark.triangle")
            }
            if result.failedCount > 0 {
                resultRow("失败", count: result.failedCount, color: SemanticColor.danger, icon: "xmark.circle")
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
}

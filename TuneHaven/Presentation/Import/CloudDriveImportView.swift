import SwiftUI
import UniformTypeIdentifiers

struct CloudDriveImportView: View {
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var showDocumentPicker = false
    @State private var isImporting = false
    @State private var progress: ImportProgress?
    @State private var importResult: ImportResult?
    @State private var selectedProvider: (any CloudDriveProvider)?
    @State private var showBaiduGuide = false

    private let providers = CloudDriveRegistry.allProviders

    var body: some View {
        NavigationStack {
            List {
                providersSection
                guideSection
                if isImporting, let p = progress {
                    importingSection(p)
                }
                if let result = importResult {
                    importResultSection(result)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("云盘导入")
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
            allowedContentTypes: [.audio, .mpeg4Audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                startImport(urls: urls)
            }
        }
        .alert("即将跳转到百度网盘", isPresented: $showBaiduGuide) {
            Button("取消", role: .cancel) { }
            Button("打开百度网盘") {
                ExternalAppLauncher.openBaiduNetdisk()
            }
        } message: {
            Text("在百度网盘中：\n1. 找到并下载要导入的音乐文件\n2. 长按文件 → 打开方式\n3. 选择 TuneHaven\n文件将自动导入到音乐库")
        }
    }

    // MARK: - Providers Section

    private var providersSection: some View {
        Section {
            ForEach(providers, id: \.id) { provider in
                providerRow(provider)
            }
        } header: {
            Text("选择云盘")
                .foregroundColor(palette.textSecondary)
        }
    }

    private func providerRow(_ provider: any CloudDriveProvider) -> some View {
        Button {
            if provider.id == "baidu_netdisk" {
                showBaiduGuide = true
            } else {
                selectedProvider = provider
                showDocumentPicker = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.iconName)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.primary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.textPrimary)
                    Text(provider.description)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                if provider.isInstalled {
                    Label("已安装", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(palette.primary)
                } else {
                    Text("未检测到")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(palette.surface)
    }

    // MARK: - Guide Section

    private var guideSection: some View {
        Section {
            guideRow(step: "1", text: "点击上方百度网盘，跳转到 App")
            guideRow(step: "2", text: "找到音乐文件，先下载到手机本地")
            guideRow(step: "3", text: "下载完成后长按文件 → 打开方式")
            guideRow(step: "4", text: "选择 TuneHaven，文件将自动导入")

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(SemanticColor.warning)
                    .font(.caption)
                Text("百度网盘中的云端文件需先下载到手机本地，才能通过「打开方式」分享")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            .listRowBackground(palette.surfaceSecondary)

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(palette.primary)
                    .font(.caption)
                Text("也支持从微信、QQ、AirDrop 等 App 直接分享音频文件到本 App")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            .listRowBackground(palette.surfaceSecondary)
        } header: {
            Text("操作步骤")
                .foregroundColor(palette.textSecondary)
        }
    }

    private func guideRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(palette.primary))

            Text(text)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
        }
        .padding(.vertical, 2)
        .listRowBackground(palette.surface)
    }

    // MARK: - Importing Section

    private func importingSection(_ p: ImportProgress) -> some View {
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

    // MARK: - Result Section

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

    // MARK: - Import Logic

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
}

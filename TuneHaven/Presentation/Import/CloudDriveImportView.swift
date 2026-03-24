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
    @State private var filePickerError: String?

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
            allowedContentTypes: UTType.allSupportedAudio,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                startImport(urls: urls)
            case .failure(let error):
                filePickerError = "文件选择失败：\(error.localizedDescription)"
            }
        }
        .alert("提示", isPresented: .init(
            get: { filePickerError != nil },
            set: { if !$0 { filePickerError = nil } }
        )) {
            Button("确定") { filePickerError = nil }
        } message: {
            Text(filePickerError ?? "")
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
                    .foregroundColor(palette.textPrimary)
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

                if CloudDriveInstallChecker.isInstalled(provider) {
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
            StepGuideRow(step: "1", text: "点击上方百度网盘，跳转到 App")
            StepGuideRow(step: "2", text: "找到音乐文件，先下载到手机本地")
            StepGuideRow(step: "3", text: "下载完成后长按文件 → 打开方式")
            StepGuideRow(step: "4", text: "选择 TuneHaven，文件将自动导入")

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


    // MARK: - Importing Section

    private func importingSection(_ p: ImportProgress) -> some View {
        ImportProgressSection(progress: p) {
            importService.cancelImport()
        }
    }

    // MARK: - Result Section

    @ViewBuilder
    private func importResultSection(_ result: ImportResult) -> some View {
        ImportResultSection(result: result)
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

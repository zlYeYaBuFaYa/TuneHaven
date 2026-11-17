import SwiftUI
import UniformTypeIdentifiers

struct ImportFilesView: View {
    var initialSource: MusicImportSource? = nil
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private enum Destination: Identifiable {
        case source(MusicImportSource), premium
        var id: String {
            switch self {
            case .source(let source): return source.rawValue
            case .premium: return "premium"
            }
        }
    }

    @State private var destination: Destination?
    @State private var showDocumentPicker = false
    @State private var importResult: ImportResult?
    @State private var isImporting = false
    @State private var progress: ImportProgress?
    @State private var filePickerError: String?
    @State private var didSelectInitialSource = false
    @State private var didCancelImport = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ImportIntro(symbol: "square.and.arrow.down", title: "把喜欢的音乐带进来", message: "选择一种导入方式，音乐将保存在这台设备上，随时离线聆听。")
                        .plainListRow()
                }
                Section {
                    ForEach(MusicImportSource.allCases) { source in
                        Button { select(source) } label: {
                            ImportSourceLabel(source: source, locked: source == .webDAV && !subscriptionService.canAccess(.webDAVImport))
                        }
                        .buttonStyle(.plain)
                        .importRowSurface()
                        .disabled(importService.isImporting || isImporting)
                        .accessibilityIdentifier("import.source.\(source.rawValue)")
                    }
                } header: {
                    Text("导入方式").foregroundColor(palette.textSecondary)
                } footer: {
                    Text("支持 MP3、M4A、AAC、ALAC、WAV、FLAC、AIFF、CAF，单文件不超过 500 MB。重复文件会自动跳过。")
                        .foregroundColor(palette.textSecondary)
                }
                if isImporting {
                    ImportProgressSection(progress: progress ?? ImportProgress(currentFileName: "准备文件…", completedCount: 0, totalCount: 0, percentage: 0, estimatedRemainingSeconds: nil), isCancelling: didCancelImport) {
                        didCancelImport = true
                        importService.cancelImport()
                    }
                } else if importService.isImporting {
                    Section {
                        Label("已有导入任务正在进行，请稍后再试", systemImage: "clock")
                            .font(.subheadline).foregroundColor(palette.textSecondary).importRowSurface()
                    }
                }
                if let result = importResult {
                    ImportResultSection(result: result, wasCancelled: didCancelImport)
                }
                if let error = filePickerError {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundColor(palette.textPrimary).importRowSurface()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("导入音乐")
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.foregroundColor(palette.textPrimary)
                }
            }
        }
        .tint(palette.accent)
        .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: UTType.allSupportedAudio, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                filePickerError = nil
                startImport(urls: urls)
            case .failure(let error):
                filePickerError = ImportPickerFailure.message(for: error)
            }
        }
        .sheet(item: $destination) { destination in
            Group {
                switch destination {
                case .source(.appleMusic): AppleMusicImportView()
                case .source(.cloudDrive): CloudDriveImportView()
                case .source(.wifi): WiFiTransferView()
                case .source(.webDAV): WebDAVAccountListView()
                case .source(.files): EmptyView()
                case .premium: PaywallView(triggerFeature: .webDAVImport)
                }
            }
            .sheetBackground()
            .environment(\.themePalette, palette)
        }
        .task {
            guard !didSelectInitialSource, let initialSource else { return }
            didSelectInitialSource = true
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            select(initialSource)
        }
    }

    private func select(_ source: MusicImportSource) {
        guard !isImporting, !importService.isImporting else { return }
        filePickerError = nil
        if source == .files {
            showDocumentPicker = true
        } else if source == .webDAV && !subscriptionService.canAccess(.webDAVImport) {
            destination = .premium
        } else {
            destination = .source(source)
        }
    }

    private func startImport(urls: [URL]) {
        guard !isImporting else { return }
        isImporting = true
        didCancelImport = false
        importResult = nil
        progress = nil
        Task {
            let result = await importService.importFromFiles(urls: urls) { progress = $0 }
            isImporting = false
            importResult = result
            await libraryService.loadSongs()
        }
    }
}

import SwiftUI

struct ShareReceiveView: View {
    @EnvironmentObject private var shareService: ShareService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var phase: ReceivePhase = .scanning
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private enum ReceivePhase {
        case scanning
        case analyzing
        case preview(ShareAnalysis)
        case transferring
        case completed(ShareTransferResult)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .scanning:
                    scanView
                case .analyzing:
                    analyzingView
                case .preview(let analysis):
                    previewView(analysis)
                case .transferring:
                    transferringView
                case .completed(let result):
                    completedView(result)
                }
            }
            .navigationTitle("接收")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { handleClose() }
                        .foregroundColor(palette.primary)
                }
            }
        }
        .alert("错误", isPresented: $showErrorAlert) {
            Button("确定") {
                phase = .scanning
            }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .interactiveDismissDisabled(isTransferring)
    }

    private var isTransferring: Bool {
        if case .transferring = phase { return true }
        return false
    }

    // MARK: - Scan

    private var scanView: some View {
        ZStack {
            QRScannerView { scannedContent in
                phase = .analyzing
                Task { await handleScanned(scannedContent) }
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                Text("扫描发送端二维码")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(palette.primary)
            Text("正在分析分享内容...")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveBackground()
    }

    // MARK: - Preview

    private func previewView(_ analysis: ShareAnalysis) -> some View {
        VStack(spacing: 0) {
            ShareContentPreviewView(analysis: analysis)

            Button {
                phase = .transferring
                Task { await executeReceive() }
            } label: {
                Text("开始接收")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(palette.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .adaptiveBackground()
    }

    // MARK: - Transferring

    private var transferringView: some View {
        VStack(spacing: 20) {
            Spacer()

            if let progress = shareService.receiveProgress {
                VStack(spacing: 12) {
                    Text(progress.phase.label)
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)

                    ProgressView(value: progress.fractionCompleted)
                        .tint(palette.primary)
                        .padding(.horizontal, 32)

                    HStack {
                        if let name = progress.currentFileName {
                            Text(name)
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(progress.current)/\(progress.total)")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                    .padding(.horizontal, 32)
                }

                if let analysis = shareService.analysis {
                    Text("已跳过 \(analysis.skippedSongs.count) 首已有歌曲")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .padding(.top, 8)
                }
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(palette.primary)
                Text("准备接收中...")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveBackground()
    }

    // MARK: - Completed

    private func completedView(_ result: ShareTransferResult) -> some View {
        List {
            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("接收完成")
                        .font(.title2.bold())
                        .foregroundColor(palette.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            }

            if result.songsReceived > 0 || result.songsSkipped > 0 || result.failedCount > 0 {
                Section {
                    if result.songsReceived > 0 {
                        infoRow("新增", value: "\(result.songsReceived) 首", icon: "plus.circle.fill", color: .green)
                    }
                    if result.songsSkipped > 0 {
                        infoRow("跳过（本地已有）", value: "\(result.songsSkipped) 首", icon: "arrow.right.circle.fill", color: .orange)
                    }
                    if result.failedCount > 0 {
                        infoRow("失败", value: "\(result.failedCount) 首", icon: "xmark.circle.fill", color: .red)
                    }
                } header: {
                    Text("歌曲")
                        .foregroundColor(palette.textSecondary)
                }
            }

            if result.playlistsCreated > 0 || result.localSongsLinked > 0 {
                Section {
                    if result.playlistsCreated > 0 {
                        infoRow("创建歌单", value: "\(result.playlistsCreated) 个", icon: "list.bullet.rectangle.fill", color: palette.primary)
                    }
                    if result.localSongsLinked > 0 {
                        infoRow("关联本地歌曲", value: "\(result.localSongsLinked) 首", icon: "link.circle.fill", color: palette.primary)
                    }
                } header: {
                    Text("歌单")
                        .foregroundColor(palette.textSecondary)
                }
            }

            Section {
                Button {
                    Task { await libraryService.loadSongs() }
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(palette.primary)
                        .cornerRadius(10)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(label)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(palette.textPrimary)
        }
    }

    private func handleScanned(_ content: String) async {
        do {
            let analysis = try await shareService.connectAndAnalyze(qrContent: content)
            phase = .preview(analysis)
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func executeReceive() async {
        do {
            let result = try await shareService.executeReceive()
            phase = .completed(result)
        } catch {
            shareService.cancelReceive()
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func handleClose() {
        if shareService.isReceiving {
            shareService.cancelReceive()
        }
        dismiss()
    }

}

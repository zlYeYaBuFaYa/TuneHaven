import SwiftUI

struct ShareSendView: View {
    @EnvironmentObject private var shareService: ShareService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var phase: SendPhase = .selectType
    @State private var qrContent: String?
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private enum SendPhase {
        case selectType
        case selectSongs
        case selectPlaylists
        case waitingConnection
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .selectType:
                    selectTypeView
                case .selectSongs:
                    ShareSongSelectorView { songs in
                        Task { await prepareSend { try await shareService.prepareSendSongs(songs) } }
                    }
                case .selectPlaylists:
                    SharePlaylistSelectorView { details in
                        Task { await prepareSend { try await shareService.prepareSendPlaylists(details) } }
                    }
                case .waitingConnection:
                    waitingView
                }
            }
            .navigationTitle(phase == .selectType ? "发送" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { handleClose() }
                        .foregroundColor(palette.primary)
                }
            }
        }
        .alert("错误", isPresented: $showErrorAlert) {
            Button("确定") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    // MARK: - Select Type

    private var selectTypeView: some View {
        List {
            Section {
                Button {
                    phase = .selectSongs
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("分享歌曲")
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)
                            Text("选择歌曲发送到其他设备")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "music.note.list")
                            .foregroundColor(palette.primary)
                    }
                }

                Button {
                    phase = .selectPlaylists
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("分享歌单")
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)
                            Text("选择歌单连同歌曲发送")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(palette.primary)
                    }
                }
            } header: {
                Text("选择分享内容")
                    .foregroundColor(palette.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
    }

    // MARK: - Waiting / Transferring / Completed

    private var sendPhaseState: SendPhaseState {
        guard let phase = shareService.sendProgress?.phase else { return .active }
        switch phase {
        case .completed: return .completed
        case .failed(let msg): return .failed(msg)
        default: return .active
        }
    }

    private enum SendPhaseState {
        case active
        case completed
        case failed(String)
    }

    @ViewBuilder
    private var waitingView: some View {
        switch sendPhaseState {
        case .completed:
            sendCompletedView
        case .failed(let message):
            sendDisconnectedView(message: message)
        case .active:
            sendActiveView
        }
    }

    private var sendActiveView: some View {
        VStack(spacing: 24) {
            if let qr = qrContent {
                Text("请用另一台设备的 TuneHaven 扫描此二维码")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                QRCodeView(content: qr)
                    .frame(width: 220, height: 220)
                    .padding()

                if let receiver = shareService.connectedReceiver {
                    Label(receiver, systemImage: "iphone.radiowaves.left.and.right")
                        .font(.subheadline)
                        .foregroundColor(palette.primary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(palette.textSecondary)
                        Text("等待连接...")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }

            if let progress = shareService.sendProgress {
                VStack(spacing: 8) {
                    ProgressView(value: progress.fractionCompleted)
                        .tint(palette.primary)
                    HStack {
                        Text(progress.phase.label)
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        Text("\(progress.current)/\(progress.total)")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                    if let name = progress.currentFileName {
                        Text(name)
                            .font(.caption2)
                            .foregroundColor(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveBackground()
    }

    private var sendCompletedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("发送完成")
                .font(.title2.bold())
                .foregroundColor(palette.textPrimary)

            if let progress = shareService.sendProgress {
                Text("共处理 \(progress.total) 首歌曲")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()

            Button {
                shareService.stopSending()
                dismiss()
            } label: {
                Text("完成")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(palette.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveBackground()
    }

    private func sendDisconnectedView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56))
                .foregroundColor(.orange)

            Text("连接已断开")
                .font(.title2.bold())
                .foregroundColor(palette.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let progress = shareService.sendProgress, progress.current > 0 {
                Text("已传输 \(progress.current) 首歌曲")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()

            Button {
                shareService.stopSending()
                dismiss()
            } label: {
                Text("关闭")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(palette.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveBackground()
    }

    // MARK: - Helpers

    private func prepareSend(_ action: @escaping () async throws -> String) async {
        do {
            let qr = try await action()
            qrContent = qr
            phase = .waitingConnection
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func handleClose() {
        if shareService.isSending {
            shareService.stopSending()
        }
        dismiss()
    }

}

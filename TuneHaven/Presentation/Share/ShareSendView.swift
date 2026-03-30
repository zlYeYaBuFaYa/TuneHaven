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

    // MARK: - Waiting for Connection

    private var waitingView: some View {
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

import SwiftUI

struct ShareTransferView: View {
    @EnvironmentObject private var shareService: ShareService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var activeMode: TransferMode?

    private enum TransferMode: Identifiable {
        case send, receive
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        activeMode = .send
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("发送")
                                    .font(.subheadline)
                                    .foregroundColor(palette.textPrimary)
                                Text("分享歌曲或歌单给其他设备")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(palette.primary)
                        }
                    }

                    Button {
                        activeMode = .receive
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("接收")
                                    .font(.subheadline)
                                    .foregroundColor(palette.textPrimary)
                                Text("扫描二维码从其他设备接收")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(palette.primary)
                        }
                    }
                } header: {
                    Text("选择操作")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("确保两台设备连接同一 Wi-Fi 网络")
                        .foregroundColor(palette.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("分享传输")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.primary)
                }
            }
            .fullScreenCover(item: $activeMode) { mode in
                Group {
                    switch mode {
                    case .send:
                        ShareSendView()
                    case .receive:
                        ShareReceiveView()
                    }
                }
                .environment(\.themePalette, palette)
                .environmentObject(shareService)
                .environmentObject(libraryService)
                .environmentObject(playlistService)
            }
        }
    }
}

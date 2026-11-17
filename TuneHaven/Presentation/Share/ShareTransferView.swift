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
                    FlowIntro(symbol: "iphone.radiowaves.left.and.right", title: "让音乐，在设备间相遇", message: "选择发送或接收，两台设备需要连接同一 WiFi。")
                        .plainListRow()
                }
                Section {
                    Button { activeMode = .send } label: {
                        FlowChoiceLabel(symbol: "square.and.arrow.up", title: "发送", message: "分享歌曲或歌单给其他设备")
                    }
                    .buttonStyle(.plain).flowRowSurface()
                    Button { activeMode = .receive } label: {
                        FlowChoiceLabel(symbol: "qrcode.viewfinder", title: "接收", message: "扫描发送端的二维码，先预览再接收")
                    }
                    .buttonStyle(.plain).flowRowSurface()
                } header: {
                    Text("选择操作")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("确保两台设备连接同一 Wi-Fi 网络")
                        .foregroundColor(palette.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("分享传输")
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.accent)
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

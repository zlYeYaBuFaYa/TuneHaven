import SwiftUI
import MediaPlayer

struct AppleMusicImportView: View {
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = AppleMusicImportViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.authStatus {
                case .authorized:
                    authorizedContent
                case .denied, .restricted:
                    permissionDeniedView
                default:
                    ProgressView("正在请求权限...")
                }
            }
            .adaptiveBackground()
            .navigationTitle("Apple Music 资料库")
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
                if vm.authStatus == .authorized && !vm.selectedIds.isEmpty && !vm.isImporting {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入 (\(vm.selectedIds.count))") {
                            Task { await vm.startImport(importService: importService, libraryService: libraryService) }
                        }
                        .foregroundColor(palette.accent)
                        .disabled(importService.isImporting || vm.isImporting)
                    }
                }
            }
        }
        .task { await vm.checkAuthorization() }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        if vm.isLoading {
            ProgressView("正在扫描资料库...")
        } else if vm.tracks.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(palette.iconSecondary)
                Text("还没有可导入的本地音乐")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Text("Apple Music 资料库中没有可导入的本地音乐\n（DRM 保护的流媒体歌曲无法导入）")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        } else {
            VStack(spacing: 0) {
                searchBar
                selectionToolbar
                songList
            }
        }
    }

    private var searchBar: some View {
        SearchBar(text: $vm.searchText, placeholder: "搜索歌曲、艺术家")
    }

    private var selectionToolbar: some View {
        HStack {
            Text("\(vm.filteredTracks.count) 首可导入")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
            Spacer()
            Button {
                vm.toggleSelectAll()
            } label: {
                Text(vm.selectedIds.count == vm.filteredTracks.count ? "取消全选" : "全选")
                    .font(.caption)
                    .foregroundColor(palette.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .disabled(vm.isImporting)
    }

    private var songList: some View {
        List {
            if vm.isImporting {
                Section {
                    importingBanner.importRowSurface()
                } footer: {
                    Text("关闭页面后，导入仍会继续。").foregroundColor(palette.textSecondary)
                }
            }
            if let result = vm.importResult {
                ImportResultSection(result: result)
                if vm.transcodedCount > 0 {
                    Text("\(vm.transcodedCount) 首无法原样导出，已转码为 AAC")
                        .font(.footnote).foregroundColor(palette.textSecondary).plainListRow()
                }
            }
            Section {
                if vm.filteredTracks.isEmpty {
                    Text("没有找到相关音乐，请试试其他关键词。")
                        .font(.subheadline).foregroundColor(palette.textSecondary).plainListRow()
                }
                ForEach(vm.filteredTracks) { track in
                    Button { vm.toggleSelection(track.id) } label: { trackRow(track) }
                        .buttonStyle(.plain)
                        .disabled(vm.isImporting)
                        .importRowSurface()
                        .accessibilityLabel("\(track.title)，\(track.artist)")
                        .accessibilityValue(vm.selectedIds.contains(track.id) ? "已选择" : "未选择")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
    }

    private func trackRow(_ track: AppleMusicTrack) -> some View {
        let isSelected = vm.selectedIds.contains(track.id)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? palette.accent : palette.textSecondary)
                .font(.title3)

            ArtworkThumbnail(artwork: vm.artwork(for: track.id))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text("\(track.artist) · \(track.album)")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(track.duration.formattedTime)
                .font(.caption.monospacedDigit())
                .foregroundColor(palette.textSecondary)
        }
        .contentShape(Rectangle())
    }

    private var importingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("正在导入...")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                Text("\(vm.importProgress.current)/\(vm.importProgress.total)")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private struct ArtworkThumbnail: View {
        let artwork: MPMediaItemArtwork?
        @Environment(\.themePalette) private var palette
        @State private var image: UIImage?

        var body: some View {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(palette.surfaceSecondary)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundColor(palette.textSecondary)
                        }
                }
            }
            .task {
                guard let artwork, image == nil else { return }
                image = artwork.image(at: CGSize(width: 44, height: 44))
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(palette.iconSecondary)
            Text("需要访问音乐资料库权限")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
            Text("请在系统设置中允许本应用访问您的音乐资料库")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("打开系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundColor(palette.accent)
        }
        .padding()
    }
}

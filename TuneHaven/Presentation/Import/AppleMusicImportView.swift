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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.primary)
                }
                if vm.authStatus == .authorized && !vm.selectedIds.isEmpty && !vm.isImporting {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入 (\(vm.selectedIds.count))") {
                            Task { await vm.startImport(importService: importService, libraryService: libraryService) }
                        }
                        .foregroundColor(palette.primary)
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
        } else if vm.mediaItems.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(palette.iconSecondary)
                Text("未找到本地音乐文件")
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
                if vm.isImporting {
                    importingBanner
                }

                if let result = vm.importResult {
                    importResultBanner(result)
                }

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
            Text("\(vm.filteredItems.count) 首可导入")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
            Spacer()
            Button {
                vm.toggleSelectAll()
            } label: {
                Text(vm.selectedIds.count == vm.filteredItems.count ? "取消全选" : "全选")
                    .font(.caption)
                    .foregroundColor(palette.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var songList: some View {
        List {
            ForEach(vm.filteredItems, id: \.persistentID) { item in
                mediaItemRow(item)
                    .listRowBackground(palette.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func mediaItemRow(_ item: MPMediaItem) -> some View {
        let isSelected = vm.selectedIds.contains(item.persistentID)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? palette.primary : palette.textTertiary)
                .font(.title3)

            ArtworkThumbnail(artwork: item.artwork)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "未知歌曲")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text("\(item.artist ?? SongDefaults.unknownArtist) · \(item.albumTitle ?? SongDefaults.unknownAlbum)")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(TimeInterval(item.playbackDuration).formattedTime)
                .font(.caption.monospacedDigit())
                .foregroundColor(palette.textTertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            vm.toggleSelection(item.persistentID)
        }
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
        .padding()
        .background(palette.surface)
    }

    private func importResultBanner(_ result: ImportResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(palette.primary)
            Text("导入完成：成功 \(result.successCount) 首")
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            if result.skippedDuplicateCount > 0 {
                Text("跳过 \(result.skippedDuplicateCount) 首重复")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(palette.surface)
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
                                .foregroundColor(palette.textTertiary)
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
            .foregroundColor(palette.primary)
        }
        .padding()
    }
}

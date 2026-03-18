import SwiftUI
import MediaPlayer
import AVFoundation

struct AppleMusicImportView: View {
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var mediaItems: [MPMediaItem] = []
    @State private var selectedIds: Set<MPMediaEntityPersistentID> = []
    @State private var authStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var importProgress: (current: Int, total: Int) = (0, 0)
    @State private var importResult: ImportResult?
    @State private var searchText = ""

    private var filteredItems: [MPMediaItem] {
        if searchText.isEmpty { return mediaItems }
        let q = searchText.lowercased()
        return mediaItems.filter {
            ($0.title ?? "").lowercased().contains(q) ||
            ($0.artist ?? "").lowercased().contains(q) ||
            ($0.albumTitle ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch authStatus {
                case .authorized:
                    authorizedContent
                case .denied, .restricted:
                    permissionDeniedView
                default:
                    ProgressView("正在请求权限...")
                }
            }
            .background(palette.background)
            .navigationTitle("Apple Music 资料库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.primary)
                }
                if authStatus == .authorized && !selectedIds.isEmpty && !isImporting {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入 (\(selectedIds.count))") {
                            Task { await startImport() }
                        }
                        .foregroundColor(palette.primary)
                    }
                }
            }
        }
        .task { await checkAuthorization() }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        if isLoading {
            ProgressView("正在扫描资料库...")
        } else if mediaItems.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
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
                if isImporting {
                    importingBanner
                }

                if let result = importResult {
                    importResultBanner(result)
                }

                searchBar
                selectionToolbar
                songList
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(palette.textTertiary)
            TextField("搜索歌曲、艺术家", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(palette.textPrimary)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.surfaceSecondary)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var selectionToolbar: some View {
        HStack {
            Text("\(filteredItems.count) 首可导入")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
            Spacer()
            Button {
                if selectedIds.count == filteredItems.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(filteredItems.map { $0.persistentID })
                }
            } label: {
                Text(selectedIds.count == filteredItems.count ? "取消全选" : "全选")
                    .font(.caption)
                    .foregroundColor(palette.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var songList: some View {
        List {
            ForEach(filteredItems, id: \.persistentID) { item in
                mediaItemRow(item)
                    .listRowBackground(palette.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func mediaItemRow(_ item: MPMediaItem) -> some View {
        let isSelected = selectedIds.contains(item.persistentID)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? palette.primary : palette.textTertiary)
                .font(.title3)

            if let artwork = item.artwork, let img = artwork.image(at: CGSize(width: 44, height: 44)) {
                Image(uiImage: img)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "未知歌曲")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text("\(item.artist ?? "未知艺术家") · \(item.albumTitle ?? "未知专辑")")
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
            if isSelected {
                selectedIds.remove(item.persistentID)
            } else {
                selectedIds.insert(item.persistentID)
            }
        }
    }

    private var importingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("正在导入...")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                Text("\(importProgress.current)/\(importProgress.total)")
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

    private func checkAuthorization() async {
        let status = MPMediaLibrary.authorizationStatus()
        if status == .notDetermined {
            let granted = await withCheckedContinuation { cont in
                MPMediaLibrary.requestAuthorization { s in cont.resume(returning: s) }
            }
            authStatus = granted
        } else {
            authStatus = status
        }

        if authStatus == .authorized {
            await loadMediaItems()
        }
    }

    private func loadMediaItems() async {
        isLoading = true
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: false,
            forProperty: MPMediaItemPropertyIsCloudItem
        ))
        let items = (query.items ?? []).filter { $0.assetURL != nil }
        mediaItems = items
        isLoading = false
    }

    private func startImport() async {
        let selected = mediaItems.filter { selectedIds.contains($0.persistentID) }
        guard !selected.isEmpty else { return }

        isImporting = true
        importResult = nil
        importProgress = (0, selected.count)

        var successCount = 0
        var duplicateCount = 0
        var failedCount = 0
        var details: [SingleImportResult] = []

        for (i, item) in selected.enumerated() {
            importProgress = (i + 1, selected.count)

            guard let assetURL = item.assetURL else {
                failedCount += 1
                details.append(SingleImportResult(fileName: item.title ?? "unknown", status: .failed, song: nil, errorMessage: "无法访问音频文件"))
                continue
            }

            if let exportedURL = await exportMediaItem(item, assetURL: assetURL) {
                let artwork = item.artwork?.image(at: CGSize(width: 600, height: 600))
                let result = await importService.processAppleMusicFile(
                    tempURL: exportedURL,
                    originalFilename: exportedURL.lastPathComponent,
                    title: item.title,
                    artist: item.artist,
                    album: item.albumTitle,
                    coverImage: artwork
                )
                details.append(result)
                switch result.status {
                case .success, .successIncompleteMetadata: successCount += 1
                case .skippedDuplicate: duplicateCount += 1
                default: failedCount += 1
                }
                try? FileManager.default.removeItem(at: exportedURL)
            } else {
                failedCount += 1
                details.append(SingleImportResult(fileName: item.title ?? "unknown", status: .failed, song: nil, errorMessage: "导出音频失败"))
            }
        }

        isImporting = false
        importResult = ImportResult(
            successCount: successCount,
            skippedDuplicateCount: duplicateCount,
            skippedFormatCount: 0,
            failedCount: failedCount,
            incompleteMetadataCount: 0,
            skippedOversizeCount: 0,
            details: details
        )
        selectedIds.removeAll()
        await libraryService.loadSongs()
    }

    private func exportMediaItem(_ item: MPMediaItem, assetURL: URL) async -> URL? {
        let baseName = sanitizeFileName(item.title ?? "track", artist: item.artist)

        // Strategy 1: Passthrough export to m4a
        if let url = await tryExport(assetURL: assetURL, fileName: baseName + ".m4a", fileType: .m4a, preset: AVAssetExportPresetPassthrough) {
            return url
        }

        // Strategy 2: Passthrough export to mp4 (broader container compatibility)
        if let url = await tryExport(assetURL: assetURL, fileName: baseName + ".m4a", fileType: .mp4, preset: AVAssetExportPresetPassthrough) {
            return url
        }

        // Strategy 3: Re-encode to m4a (handles incompatible source formats)
        if let url = await tryExport(assetURL: assetURL, fileName: baseName + ".m4a", fileType: .m4a, preset: AVAssetExportPresetAppleM4A) {
            return url
        }

        // Strategy 4: Direct file copy for accessible file URLs
        if assetURL.isFileURL {
            let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + assetURL.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: assetURL, to: copyURL)
                return copyURL
            } catch {
                AppLogger.shared.error(error, context: "Apple Music 文件复制失败")
                return nil
            }
        }

        return nil
    }

    private func tryExport(assetURL: URL, fileName: String, fileType: AVFileType, preset: String) async -> URL? {
        let asset = AVURLAsset(url: assetURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + fileName)
        session.outputURL = tempURL
        session.outputFileType = fileType

        await session.export()

        if session.status == .completed { return tempURL }

        try? FileManager.default.removeItem(at: tempURL)
        return nil
    }

    private func sanitizeFileName(_ title: String, artist: String?) -> String {
        let base = artist != nil ? "\(artist!) - \(title)" : title
        let cleaned = base.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return String(cleaned.prefix(100))
    }
}

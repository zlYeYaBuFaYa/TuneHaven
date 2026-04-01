import Foundation
import MediaPlayer
import AVFoundation
import UIKit
import Combine

@MainActor
final class AppleMusicImportViewModel: ObservableObject {
    @Published private(set) var mediaItems: [MPMediaItem] = []
    @Published var selectedIds: Set<MPMediaEntityPersistentID> = []
    @Published private(set) var authStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading = true
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: (current: Int, total: Int) = (0, 0)
    @Published var importResult: ImportResult?
    @Published var searchText = ""
    @Published private(set) var filteredItems: [MPMediaItem] = []

    init() {
        Publishers.CombineLatest(
            $searchText
                .removeDuplicates()
                .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                .prepend(""),
            $mediaItems
        )
        .map { query, items -> [MPMediaItem] in
            if query.isEmpty { return items }
            let q = query.lowercased()
            return items.filter {
                ($0.title ?? "").lowercased().contains(q) ||
                ($0.artist ?? "").lowercased().contains(q) ||
                ($0.albumTitle ?? "").lowercased().contains(q)
            }
        }
        .assign(to: &$filteredItems)
    }

    func checkAuthorization() async {
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

    func toggleSelection(_ persistentID: MPMediaEntityPersistentID) {
        if selectedIds.contains(persistentID) {
            selectedIds.remove(persistentID)
        } else {
            selectedIds.insert(persistentID)
        }
    }

    func toggleSelectAll() {
        if selectedIds.count == filteredItems.count {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(filteredItems.map { $0.persistentID })
        }
    }

    func startImport(importService: ImportService, libraryService: MusicLibraryService) async {
        let selected = mediaItems.filter { selectedIds.contains($0.persistentID) }
        guard !selected.isEmpty else { return }

        isImporting = true
        importResult = nil
        importProgress = (0, selected.count)

        var successCount = 0
        var duplicateCount = 0
        var failedCount = 0
        var incompleteMetadataCount = 0
        var details: [SingleImportResult] = []

        var lastExportedURL: URL?
        for (i, item) in selected.enumerated() {
            if Task.isCancelled {
                if let url = lastExportedURL { try? FileManager.default.removeItem(at: url) }
                break
            }
            lastExportedURL = nil
            importProgress = (i + 1, selected.count)

            guard let assetURL = item.assetURL else {
                failedCount += 1
                details.append(SingleImportResult(fileName: item.title ?? "unknown", status: .failed, song: nil, errorMessage: "无法访问音频文件"))
                continue
            }

            if let exportedURL = await exportMediaItem(item, assetURL: assetURL) {
                lastExportedURL = exportedURL
                let artworkData = item.artwork?.image(at: CGSize(width: 400, height: 400))?.jpegData(compressionQuality: 0.8)
                let result = await importService.processAppleMusicFile(
                    tempURL: exportedURL,
                    originalFilename: exportedURL.lastPathComponent,
                    title: item.title,
                    artist: item.artist,
                    album: item.albumTitle,
                    coverData: artworkData
                )
                details.append(result)
                switch result.status {
                case .success: successCount += 1
                case .successIncompleteMetadata: successCount += 1; incompleteMetadataCount += 1
                case .skippedDuplicate: duplicateCount += 1
                default: failedCount += 1
                }
                do {
                    try FileManager.default.removeItem(at: exportedURL)
                } catch {
                    AppLogger.shared.debug("临时文件清理失败: \(exportedURL.lastPathComponent) - \(error.localizedDescription)")
                }
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
            incompleteMetadataCount: incompleteMetadataCount,
            skippedOversizeCount: 0,
            details: details
        )
        selectedIds.removeAll()
        await libraryService.loadSongs()
    }

    // MARK: - Private

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

    private func exportMediaItem(_ item: MPMediaItem, assetURL: URL) async -> URL? {
        let baseName = Self.sanitizeFileName(item.title ?? "track", artist: item.artist)

        if let url = await tryExport(assetURL: assetURL, fileName: baseName + ".m4a", fileType: .m4a, preset: AVAssetExportPresetPassthrough) {
            return url
        }

        if let url = await tryExport(assetURL: assetURL, fileName: baseName + ".m4a", fileType: .mp4, preset: AVAssetExportPresetPassthrough) {
            return url
        }

        if let url = await tryExport(assetURL: assetURL, fileName: baseName + ".m4a", fileType: .m4a, preset: AVAssetExportPresetAppleM4A) {
            return url
        }

        if assetURL.isFileURL {
            return await Task.detached {
                let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + assetURL.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: assetURL, to: copyURL)
                    return copyURL
                } catch {
                    AppLogger.shared.error(error, context: "Apple Music 文件复制失败")
                    return nil
                }
            }.value
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

    private static let unsafeFileNameCharacters = CharacterSet(charactersIn: "/:\\?*\"<>|\0")

    static func sanitizeFileName(_ title: String, artist: String?) -> String {
        let base = artist.map { "\($0) - \(title)" } ?? title
        let cleaned = base.unicodeScalars
            .filter { !unsafeFileNameCharacters.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
        return String(cleaned.prefix(100))
    }
}

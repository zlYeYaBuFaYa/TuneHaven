import Foundation
import MediaPlayer
import UIKit
import Combine

/// 列表用的轻量快照。`MPMediaItem` 的属性每次读取都要查系统媒体库，
/// 列表刷新时直接读会让每次进度更新都卡上秒级，所以加载时一次性读出来。
struct AppleMusicTrack: Identifiable, Hashable {
    let id: MPMediaEntityPersistentID
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let searchKey: String

    init(item: MPMediaItem) {
        id = item.persistentID
        title = item.title ?? "未知歌曲"
        artist = item.artist ?? SongDefaults.unknownArtist
        album = item.albumTitle ?? SongDefaults.unknownAlbum
        duration = item.playbackDuration
        searchKey = "\(title)\n\(artist)\n\(album)".lowercased()
    }
}

/// 导出前的查重：歌名 + 艺术家相同且时长相差不超过 1.5 秒，视为已导入，直接跳过不导出。
/// 漏判的重复仍会在入库时被文件哈希拦下。
struct AppleMusicDuplicateIndex: Sendable {
    private static let durationTolerance: TimeInterval = 1.5
    private var durationsByKey: [String: [TimeInterval]] = [:]

    init(songs: [Song]) {
        for song in songs where !song.isAudioMissing {
            durationsByKey[Self.key(title: song.title, artist: song.artist), default: []].append(song.duration)
        }
    }

    func contains(title: String, artist: String, duration: TimeInterval) -> Bool {
        guard let durations = durationsByKey[Self.key(title: title, artist: artist)] else { return false }
        return durations.contains { abs($0 - duration) <= Self.durationTolerance }
    }

    private static func key(title: String, artist: String) -> String {
        "\(title.trimmingCharacters(in: .whitespaces).lowercased())\u{1F}\(artist.trimmingCharacters(in: .whitespaces).lowercased())"
    }
}

@MainActor
final class AppleMusicImportViewModel: ObservableObject {
    /// 同时导出的歌曲数。导出主要等待 IO，2 首即可把等待时间重叠起来。
    private static let maxConcurrentExports = 2

    @Published private(set) var tracks: [AppleMusicTrack] = []
    @Published var selectedIds: Set<MPMediaEntityPersistentID> = []
    @Published private(set) var authStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading = true
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: (current: Int, total: Int) = (0, 0)
    @Published var importResult: ImportResult?
    @Published private(set) var transcodedCount = 0
    @Published var searchText = ""
    @Published private(set) var filteredTracks: [AppleMusicTrack] = []

    private var itemsByID: [MPMediaEntityPersistentID: MPMediaItem] = [:]

    init() {
        Publishers.CombineLatest(
            $searchText
                .removeDuplicates()
                .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                .prepend(""),
            $tracks
        )
        .map { query, tracks -> [AppleMusicTrack] in
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            if q.isEmpty { return tracks }
            return tracks.filter { $0.searchKey.contains(q) }
        }
        .assign(to: &$filteredTracks)
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

    func artwork(for id: MPMediaEntityPersistentID) -> MPMediaItemArtwork? {
        itemsByID[id]?.artwork
    }

    func toggleSelection(_ persistentID: MPMediaEntityPersistentID) {
        if selectedIds.contains(persistentID) {
            selectedIds.remove(persistentID)
        } else {
            selectedIds.insert(persistentID)
        }
    }

    func toggleSelectAll() {
        if selectedIds.count == filteredTracks.count {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(filteredTracks.map(\.id))
        }
    }

    func startImport(importService: ImportService, libraryService: MusicLibraryService) async {
        let selected = tracks.filter { selectedIds.contains($0.id) }
        guard !selected.isEmpty else { return }

        guard importService.beginBatchImport() else {
            importResult = ImportResult(
                successCount: 0, skippedDuplicateCount: 0, skippedFormatCount: 0,
                failedCount: selected.count, incompleteMetadataCount: 0, skippedOversizeCount: 0,
                details: [SingleImportResult(fileName: "", status: .failed, song: nil, errorMessage: "已有导入或备份任务正在进行")]
            )
            return
        }
        defer { importService.endBatchImport() }

        isImporting = true
        importResult = nil
        transcodedCount = 0
        importProgress = (0, selected.count)

        let duplicates = AppleMusicDuplicateIndex(songs: await libraryService.fetchAllSongs())
        let exportDirectory = SandboxPathManager.importTempURL
        try? FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        var details: [SingleImportResult] = []
        details.reserveCapacity(selected.count)

        await withTaskGroup(of: SingleImportResult.self) { group in
            var nextIndex = 0
            func enqueueNext() {
                guard nextIndex < selected.count else { return }
                let track = selected[nextIndex]
                nextIndex += 1
                group.addTask {
                    await self.importTrack(track, duplicates: duplicates, exportDirectory: exportDirectory, importService: importService)
                }
            }

            for _ in 0..<Self.maxConcurrentExports { enqueueNext() }
            for await result in group {
                details.append(result)
                importProgress = (details.count, selected.count)
                if !Task.isCancelled { enqueueNext() }
            }
        }

        importResult = Self.summarize(details)
        isImporting = false
        selectedIds.removeAll()
        await libraryService.loadSongs()
    }

    // MARK: - Private

    private func loadMediaItems() async {
        isLoading = true
        let items = await Task.detached(priority: .userInitiated) { () -> [MPMediaItem] in
            let query = MPMediaQuery.songs()
            query.addFilterPredicate(MPMediaPropertyPredicate(
                value: false,
                forProperty: MPMediaItemPropertyIsCloudItem
            ))
            return (query.items ?? []).filter { $0.assetURL != nil }
        }.value
        itemsByID = Dictionary(items.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
        tracks = items.map(AppleMusicTrack.init)
        isLoading = false
    }

    private func importTrack(
        _ track: AppleMusicTrack,
        duplicates: AppleMusicDuplicateIndex,
        exportDirectory: URL,
        importService: ImportService
    ) async -> SingleImportResult {
        let fileName = Self.sanitizeFileName(track.title, artist: track.artist)

        if duplicates.contains(title: track.title, artist: track.artist, duration: track.duration) {
            return SingleImportResult(fileName: fileName, status: .skippedDuplicate, song: nil, errorMessage: nil)
        }
        guard let item = itemsByID[track.id], let assetURL = item.assetURL else {
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "无法访问音频文件")
        }
        guard let exported = await AppleMusicExporter.export(assetURL: assetURL, to: exportDirectory) else {
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "导出音频失败")
        }
        defer { try? FileManager.default.removeItem(at: exported.url) }

        let artworkData = item.artwork?.image(at: CGSize(width: 400, height: 400))?.jpegData(compressionQuality: 0.8)
        let result = await importService.processBatchExportedFile(
            tempURL: exported.url,
            originalFilename: "\(fileName).\(exported.fileExtension)",
            title: item.title,
            artist: item.artist,
            album: item.albumTitle,
            coverData: artworkData
        )
        if exported.transcoded, result.status == .success || result.status == .successIncompleteMetadata {
            transcodedCount += 1
        }
        return result
    }

    private static func summarize(_ details: [SingleImportResult]) -> ImportResult {
        var success = 0, duplicate = 0, failed = 0, incomplete = 0
        for result in details {
            switch result.status {
            case .success: success += 1
            case .successIncompleteMetadata: success += 1; incomplete += 1
            case .skippedDuplicate: duplicate += 1
            default: failed += 1
            }
        }
        return ImportResult(
            successCount: success,
            skippedDuplicateCount: duplicate,
            skippedFormatCount: 0,
            failedCount: failed,
            incompleteMetadataCount: incomplete,
            skippedOversizeCount: 0,
            details: details
        )
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

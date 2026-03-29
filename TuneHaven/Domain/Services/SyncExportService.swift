import Foundation

@MainActor
final class SyncExportService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var isExporting = false
    @Published private(set) var progress: SyncProgress?

    private let songRepo: SongRepository
    private let playlistService: PlaylistService
    private let groupService: PlaylistGroupService
    private let packager: SyncPackaging

    init(songRepo: SongRepository,
         playlistService: PlaylistService,
         groupService: PlaylistGroupService,
         packager: SyncPackaging) {
        self.songRepo = songRepo
        self.playlistService = playlistService
        self.groupService = groupService
        self.packager = packager
    }

    func exportSongs(_ songs: [Song]) async throws -> URL {
        log.info("开始导出 \(songs.count) 首歌曲")
        isExporting = true
        defer { isExporting = false; progress = nil }

        let url = try await packager.export(
            songs: songs,
            playlists: [],
            includeAudioFiles: true,
            groupNames: [:]
        ) { [weak self] p in
            Task { @MainActor in self?.progress = p }
        }

        log.info("歌曲导出完成: \(url.lastPathComponent)")
        return url
    }

    func exportPlaylists(
        _ playlists: [PlaylistDetail],
        includeAudioFiles: Bool
    ) async throws -> URL {
        log.info("开始导出 \(playlists.count) 个歌单, 含音频=\(includeAudioFiles)")
        isExporting = true
        defer { isExporting = false; progress = nil }

        let groupNameMap = await loadGroupNames()
        let url = try await packager.export(
            songs: [],
            playlists: playlists,
            includeAudioFiles: includeAudioFiles,
            groupNames: groupNameMap
        ) { [weak self] p in
            Task { @MainActor in self?.progress = p }
        }

        log.info("歌单导出完成: \(url.lastPathComponent)")
        return url
    }

    func exportAll(includeAudioFiles: Bool) async throws -> URL {
        log.info("开始全量导出, 含音频=\(includeAudioFiles)")
        isExporting = true
        defer { isExporting = false; progress = nil }

        await playlistService.loadPlaylists()
        var details: [PlaylistDetail] = []
        for playlist in playlistService.playlists where !playlist.isSystem {
            if let detail = await playlistService.fetchDetail(playlistId: playlist.id) {
                details.append(detail)
            }
        }

        let allSongs: [Song]
        if includeAudioFiles {
            allSongs = await songRepo.fetchAll(sortBy: .title, ascending: true)
        } else {
            allSongs = []
        }

        let groupNameMap = await loadGroupNames()
        let url = try await packager.export(
            songs: allSongs,
            playlists: details,
            includeAudioFiles: includeAudioFiles,
            groupNames: groupNameMap
        ) { [weak self] p in
            Task { @MainActor in self?.progress = p }
        }

        log.info("全量导出完成: \(url.lastPathComponent)")
        return url
    }

    private func loadGroupNames() async -> [UUID: String] {
        await groupService.loadGroups()
        return Dictionary(
            groupService.groupDetails.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func estimateSize(
        songs: [Song],
        playlists: [PlaylistDetail],
        includeAudioFiles: Bool
    ) -> String {
        let bytes = packager.estimateExportSize(
            songs: songs, playlists: playlists, includeAudioFiles: includeAudioFiles
        )
        return Self.formatFileSize(bytes)
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

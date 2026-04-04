import Foundation

@MainActor
final class PlaylistService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var playlists: [Playlist] = []

    private let repo: PlaylistRepository
    private let songRepo: SongRepository
    private let coverProcessor: CoverImageProcessing

    init(repo: PlaylistRepository,
         songRepo: SongRepository,
         coverProcessor: CoverImageProcessing) {
        self.repo = repo
        self.songRepo = songRepo
        self.coverProcessor = coverProcessor
    }

    func loadPlaylists() async {
        playlists = await repo.fetchAll()
    }

    func fetchDetail(playlistId: UUID) async -> PlaylistDetail? {
        await repo.fetchPlaylistDetail(id: playlistId)
    }

    func createPlaylist(name: String, description: String?) async throws -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.playlistNameEmpty }
        let reserved = [SystemPlaylistName.favorites, SystemPlaylistName.recentlyPlayed]
        guard !reserved.contains(trimmed) else { throw AppError.playlistNameDuplicate }
        log.info("创建歌单: \(trimmed)")
        let playlist = try await repo.create(name: trimmed, description: description)
        await loadPlaylists()
        return playlist
    }

    func updatePlaylist(id: UUID, name: String?, description: String?) async throws {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AppError.playlistNameEmpty }
            let reserved = [SystemPlaylistName.favorites, SystemPlaylistName.recentlyPlayed]
            guard !reserved.contains(trimmed) else { throw AppError.playlistNameDuplicate }
        }
        try await repo.update(id: id, name: name, description: description)
        await loadPlaylists()
    }

    func deletePlaylist(id: UUID) async throws {
        log.info("删除歌单: \(id)")
        try await repo.delete(id: id)
        await loadPlaylists()
    }

    func addSongs(_ songIds: [UUID], to playlistId: UUID) async throws {
        log.info("添加 \(songIds.count) 首歌到歌单 \(playlistId)")
        try await repo.addSongs(songIds, to: playlistId)
        await loadPlaylists()
    }

    func removeSongs(_ songIds: [UUID], from playlistId: UUID) async throws {
        log.info("从歌单 \(playlistId) 移除 \(songIds.count) 首歌")
        try await repo.removeSongs(songIds, from: playlistId)
        await loadPlaylists()
    }

    func setCustomCover(playlistId: UUID, imageData: Data) async throws {
        let imagePath = try await coverProcessor.processPlaylistCover(imageData: imageData, playlistId: playlistId)
        try await repo.setCustomCover(playlistId: playlistId, imagePath: imagePath)
        await loadPlaylists()
    }

    func regenerateAutoCover(for playlist: Playlist, songs: [Song]) async {
        let topSongs = Array(songs.prefix(4))
        let currentHash = topSongs.map { $0.fileHash }.joined(separator: ",")
        guard playlist.autoCoverHash != currentHash else { return }

        do {
            let path = try await coverProcessor.generatePlaylistGridCover(
                coverPaths: topSongs.map(\.coverImagePath),
                playlistId: playlist.id
            )
            try await repo.updateAutoCover(playlistId: playlist.id, path: path, hash: currentHash)
        } catch {
            AppLogger.shared.error(error, context: "regenerateAutoCover: 封面生成失败 \(playlist.id)")
        }
    }

    func fetchFavorites() async -> [Song] {
        let ids = await repo.fetchFavoritesSongIds()
        guard !ids.isEmpty else { return [] }
        let songs = await songRepo.fetchSongs(byIds: ids)
        return songs.sorted { ($0.favoriteDate ?? Date.distantPast) > ($1.favoriteDate ?? Date.distantPast) }
    }

    func reorderPlaylists(orderedIds: [UUID]) async throws {
        try await repo.reorder(orderedIds: orderedIds)
        await loadPlaylists()
    }

    func reorderSongs(in playlistId: UUID, orderedSongIds: [UUID]) async throws {
        try await repo.reorderSongs(in: playlistId, orderedSongIds: orderedSongIds)
    }

    func initializeSystemPlaylists() async throws {
        log.info("初始化系统歌单")
        try await repo.createSystemPlaylists()
        await loadPlaylists()
    }
}

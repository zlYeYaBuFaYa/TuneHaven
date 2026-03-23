import Foundation
import UIKit // TODO: 将封面处理逻辑（UIImage）移至 App/Infra 层以移除 UIKit 依赖

// TODO: ImageCacheManager / ThumbnailGenerator / SandboxPathManager 为 Core 层直接引用，
//       后续应提取协议并通过 init 注入，使 Domain 层不依赖具体实现。

@MainActor
final class PlaylistService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var playlists: [Playlist] = []

    private let repo: PlaylistRepository
    private let songRepo: SongRepository
    private let imageCache = ImageCacheManager.shared

    init(repo: PlaylistRepository,
         songRepo: SongRepository) {
        self.repo = repo
        self.songRepo = songRepo
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
        guard let image = UIImage(data: imageData) else {
            throw AppError.importFileCorrupted("无效的图片数据")
        }
        let thumb = ThumbnailGenerator.resize(image, to: .large)
        let url = SandboxPathManager.playlistCoverURL(playlistId: playlistId)
        guard let jpegData = thumb.jpegData(compressionQuality: 0.9) else {
            throw AppError.importFileCorrupted("无法压缩图片")
        }
        try jpegData.write(to: url)
        try await repo.setCustomCover(playlistId: playlistId, imagePath: url.lastPathComponent)
        await loadPlaylists()
    }

    func regenerateAutoCover(for playlist: Playlist, songs: [Song]) async {
        let topSongs = Array(songs.prefix(4))
        let currentHash = topSongs.map { $0.fileHash }.joined(separator: ",")
        guard playlist.autoCoverHash != currentHash else { return }

        let images: [UIImage?] = (0..<4).map { i -> UIImage? in
            guard i < topSongs.count, let path = topSongs[i].coverImagePath else { return nil }
            return imageCache.image(forKey: path)
        }

        let gridImage = ThumbnailGenerator.generateGridCover(images: images)
        let url = SandboxPathManager.playlistCoverURL(playlistId: playlist.id)
        if let data = gridImage.jpegData(compressionQuality: 0.85) {
            do {
                try data.write(to: url)
                try await repo.updateAutoCover(playlistId: playlist.id, path: url.lastPathComponent, hash: currentHash)
                imageCache.store(image: gridImage, forKey: url.lastPathComponent)
            } catch {
                AppLogger.shared.error(error, context: "regenerateAutoCover: 封面生成失败 \(playlist.id)")
            }
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

    /// 调整歌单内歌曲排序（TDD Section 3.3）
    func reorderSongs(in playlistId: UUID, orderedSongIds: [UUID]) async throws {
        try await repo.reorderSongs(in: playlistId, orderedSongIds: orderedSongIds)
    }

    func initializeSystemPlaylists() async throws {
        log.info("初始化系统歌单")
        try await repo.createSystemPlaylists()
        await loadPlaylists()
    }
}

import Foundation
import Combine

@MainActor
final class MusicLibraryService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false

    private let songRepo: SongRepository
    let imageCache: ImageCacheManaging
    private var pendingUndoTokens: [UndoToken] = []
    private var undoTimers: [UUID: Timer] = [:]

    init(songRepo: SongRepository, imageCache: ImageCacheManaging) {
        self.songRepo = songRepo
        self.imageCache = imageCache
    }

    func loadSongs(sortBy: SongSortOption = .title, ascending: Bool = true) async {
        log.info("加载音乐库，排序: \(sortBy)")
        isLoading = true
        do {
            songs = try await songRepo.fetchAll(sortBy: sortBy, ascending: ascending)
        } catch {
            log.error(error, context: "加载音乐库失败")
            songs = []
        }
        isLoading = false
    }

    func fetchSongsByArtist() async -> [ArtistGroup] {
        await songRepo.fetchArtistGroups()
    }

    func fetchSongsByAlbum() async -> [AlbumGroup] {
        await songRepo.fetchAlbumGroups()
    }

    func fetchArtistDetail(artist: String) async -> ArtistDetail {
        let artistSongs = await songRepo.fetchSongs(byArtist: artist, sortBy: .album, ascending: true)
        var albumMap: [String: [Song]] = [:]
        for song in artistSongs { albumMap[song.album, default: []].append(song) }
        let albums = albumMap.map { AlbumGroup(name: $0.key, artist: artist, year: $0.value.first?.metadata.year, songCount: $0.value.count, coverImagePath: $0.value.first?.coverImagePath) }.sorted { $0.name < $1.name }
        return ArtistDetail(name: artist, albums: albums, allSongs: artistSongs)
    }

    func fetchAlbumDetail(album: String, artist: String) async -> AlbumDetail {
        let albumSongs = await songRepo.fetchSongs(byAlbum: album, artist: artist, sortBy: .title, ascending: true)
        let sorted = albumSongs.sorted { ($0.metadata.trackNumber ?? 999) < ($1.metadata.trackNumber ?? 999) }
        return AlbumDetail(name: album, artist: artist, year: sorted.first?.metadata.year, songs: sorted, coverImagePath: sorted.first?.coverImagePath)
    }

    func softDelete(songIds: [UUID]) async throws -> UndoToken {
        log.info("软删除歌曲: \(songIds.count) 首")
        let token = try await songRepo.softDelete(ids: songIds)
        pendingUndoTokens.append(token)
        let idSet = Set(songIds)
        songs.removeAll { idSet.contains($0.id) }
        scheduleCommit(token: token)
        return token
    }

    func undoDelete(token: UndoToken) async throws {
        log.info("撤销删除")
        invalidateTimer(for: token)
        try await songRepo.undoDelete(token: token)
        pendingUndoTokens.removeAll { $0.songIds == token.songIds }
        await loadSongs()
    }

    func toggleFavorite(songId: UUID) async throws {
        log.info("切换收藏状态: \(songId)")
        try await songRepo.toggleFavorite(id: songId)
        if let index = songs.firstIndex(where: { $0.id == songId }),
           let refreshed = await songRepo.fetchSong(id: songId) {
            songs[index] = refreshed
        }
    }

    func recordPlay(songId: UUID) async throws {
        try await songRepo.recordPlay(id: songId)
    }

    func fetchRecentlyPlayed(days: Int, page: Int, pageSize: Int = 50) async -> PagedResult<Song> {
        await songRepo.fetchRecentlyPlayed(days: days, page: page, pageSize: pageSize)
    }

    func fetchSong(id: UUID) async -> Song? {
        await songRepo.fetchSong(id: id)
    }

    func fetchAllSongs(sortBy: SongSortOption = .title, ascending: Bool = true) async -> [Song] {
        do {
            return try await songRepo.fetchAll(sortBy: sortBy, ascending: ascending)
        } catch {
            log.error(error, context: "获取歌曲列表失败")
            return []
        }
    }

    func updateSongInfo(id: UUID, title: String, artist: String, album: String) async throws {
        log.info("更新歌曲信息: \(id)")
        try await songRepo.updateSongInfo(id: id, title: title, artist: artist, album: album)
        await loadSongs()
    }

    func cleanupOnLaunch() async {
        log.info("启动清理：清除待删除歌曲")
        await songRepo.cleanupPendingDeletes()
    }

    private func scheduleCommit(token: UndoToken) {
        let tokenKey = UUID()
        token.timerKey = tokenKey
        undoTimers[tokenKey]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.songRepo.commitDelete(token: token)
                } catch {
                    self.log.error(error, context: "commitDelete 失败，songIds=\(token.songIds)")
                }
                self.pendingUndoTokens.removeAll { $0.songIds == token.songIds }
                self.undoTimers.removeValue(forKey: tokenKey)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        undoTimers[tokenKey] = timer
    }

    private func invalidateTimer(for token: UndoToken) {
        guard let tokenKey = token.timerKey else { return }
        undoTimers[tokenKey]?.invalidate()
        undoTimers.removeValue(forKey: tokenKey)
    }

}

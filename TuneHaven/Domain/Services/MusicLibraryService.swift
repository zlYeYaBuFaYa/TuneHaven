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
    /// 软删除成功后发出被删歌曲 id，播放服务据此同步队列与当前歌曲
    let songsDeleted = PassthroughSubject<Set<UUID>, Never>()
    private var undoTimers: [UUID: Timer] = [:]
    private let backgroundTask: BackgroundTaskProviding?
    private var backgroundTaskID: UInt?

    init(songRepo: SongRepository, imageCache: ImageCacheManaging, backgroundTask: BackgroundTaskProviding? = nil) {
        self.songRepo = songRepo
        self.imageCache = imageCache
        self.backgroundTask = backgroundTask
    }

    /// 当前 `songs` 使用的排序。不传参数的 `loadSongs()` 沿用它，导入后刷新不会打乱用户选的排序
    private(set) var currentSort: (option: SongSortOption, ascending: Bool) = (.title, true)

    func loadSongs(sortBy: SongSortOption? = nil, ascending: Bool? = nil) async {
        let sortBy = sortBy ?? currentSort.option
        let ascending = ascending ?? currentSort.ascending
        currentSort = (sortBy, ascending)
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
        songsDeleted.send(idSet)
        scheduleCommit(token: token)
        return token
    }

    func undoDelete(token: UndoToken) async throws {
        log.info("撤销删除")
        guard pendingUndoTokens.contains(where: { $0 === token }) else {
            throw AppError.fileSystemError("撤销已过期")
        }
        invalidateTimer(for: token)
        pendingUndoTokens.removeAll { $0 === token }
        endBackgroundTaskIfIdle()
        try await songRepo.undoDelete(token: token)
        await loadSongs()
    }

    func toggleFavorite(songId: UUID) async throws {
        log.info("切换收藏状态: \(songId)")
        try await songRepo.toggleFavorite(id: songId)
        if let index = songs.firstIndex(where: { $0.id == songId }) {
            var updated = songs[index]
            updated.isFavorite.toggle()
            updated.favoriteDate = updated.isFavorite ? Date() : nil
            songs[index] = updated
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

    // MARK: - 删除提交与前后台

    /// 进后台：已到期的立即提交；还在撤销窗口内的申请后台时间等它到期，
    /// 系统收回时间前全部提交，避免挂起或被杀后文件一直留在待删除目录。
    func handleDidEnterBackground() async {
        await commitExpiredDeletes()
        guard !pendingUndoTokens.isEmpty, backgroundTaskID == nil, let backgroundTask else { return }
        backgroundTaskID = backgroundTask.beginTask { [weak self] in
            Task { @MainActor [weak self] in
                await self?.commitAllPendingDeletes()
            }
        }
    }

    /// 回到前台时补提交挂起期间到期的删除。
    func commitExpiredDeletes(now: Date = Date()) async {
        for token in pendingUndoTokens where token.expiresAt <= now {
            await commit(token)
        }
    }

    private func commitAllPendingDeletes() async {
        for token in pendingUndoTokens {
            await commit(token)
        }
        endBackgroundTaskIfIdle()
    }

    private func commit(_ token: UndoToken) async {
        // 先移出列表再提交，计时器与前后台同时触发时只提交一次
        guard pendingUndoTokens.contains(where: { $0 === token }) else { return }
        invalidateTimer(for: token)
        pendingUndoTokens.removeAll { $0 === token }
        do {
            try await songRepo.commitDelete(token: token)
        } catch {
            log.error(error, context: "commitDelete 失败，songIds=\(token.songIds)")
        }
        endBackgroundTaskIfIdle()
    }

    private func endBackgroundTaskIfIdle() {
        guard pendingUndoTokens.isEmpty, let id = backgroundTaskID else { return }
        backgroundTaskID = nil
        backgroundTask?.endTask(id)
    }

    private func scheduleCommit(token: UndoToken) {
        let tokenKey = UUID()
        token.timerKey = tokenKey
        undoTimers[tokenKey]?.invalidate()
        let interval = max(0, token.expiresAt.timeIntervalSinceNow)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.commit(token)
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

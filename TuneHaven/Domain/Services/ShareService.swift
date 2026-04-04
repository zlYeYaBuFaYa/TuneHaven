import Foundation
import UIKit

@MainActor
final class ShareService: ObservableObject, ShareDataSource {
    private let log = AppLogger.shared

    // MARK: - 发送端状态

    @Published private(set) var isSending = false
    @Published private(set) var sendProgress: ShareProgress?
    @Published private(set) var connectedReceiver: String?

    // MARK: - 接收端状态

    @Published private(set) var isReceiving = false
    @Published private(set) var receiveProgress: ShareProgress?
    @Published private(set) var analysis: ShareAnalysis?
    @Published private(set) var transferResult: ShareTransferResult?
    private var isReceiveCancelled = false

    private let songRepo: SongRepository
    private let playlistService: PlaylistService
    private let groupService: PlaylistGroupService
    private let importService: ImportService
    private let fileStorage: FileStorageProviding
    private let serverFactory: () -> ShareServerProviding
    private let clientFactory: () -> ShareClientProviding

    private let backgroundTask: BackgroundTaskProviding
    private var server: ShareServerProviding?
    private var client: ShareClientProviding?
    private var sharedSongs: [Song] = []
    private var sharedPlaylists: [PlaylistDetail] = []
    private var sharedSongIdToIndex: [UUID: Int] = [:]
    private var songIndex: [String: [Song]] = [:]
    private var backgroundTaskID: UInt = 0

    init(songRepo: SongRepository,
         playlistService: PlaylistService,
         groupService: PlaylistGroupService,
         importService: ImportService,
         fileStorage: FileStorageProviding,
         backgroundTask: BackgroundTaskProviding,
         serverFactory: @escaping () -> ShareServerProviding,
         clientFactory: @escaping () -> ShareClientProviding) {
        self.songRepo = songRepo
        self.playlistService = playlistService
        self.groupService = groupService
        self.importService = importService
        self.fileStorage = fileStorage
        self.backgroundTask = backgroundTask
        self.serverFactory = serverFactory
        self.clientFactory = clientFactory
    }

    // MARK: - 发送端 API

    func prepareSendSongs(_ songs: [Song]) async throws -> String {
        log.info("[Share] 准备分享 \(songs.count) 首歌曲")
        sharedSongs = songs
        sharedPlaylists = []
        rebuildSharedSongIndex()
        return try await startServer()
    }

    func prepareSendPlaylists(_ playlists: [PlaylistDetail]) async throws -> String {
        log.info("[Share] 准备分享 \(playlists.count) 个歌单")
        sharedPlaylists = playlists

        let seen = NSMutableSet()
        var unique: [Song] = []
        for detail in playlists {
            for song in detail.songs {
                if !seen.contains(song.id) {
                    seen.add(song.id)
                    unique.append(song)
                }
            }
        }
        sharedSongs = unique
        rebuildSharedSongIndex()
        return try await startServer()
    }

    func stopSending() {
        log.info("[Share] 停止发送")
        server?.stop()
        server?.onAudioFileServed = nil
        server?.onDeviceConnected = nil
        server?.onTransferCompleted = nil
        server?.onReceiverDisconnected = nil
        server = nil
        isSending = false
        sendProgress = nil
        connectedReceiver = nil
        clearShareData()
    }

    // MARK: - 接收端 API

    func connectAndAnalyze(qrContent: String) async throws -> ShareAnalysis {
        log.info("[Share] 开始连接并分析: \(qrContent.prefix(30))...")
        isReceiving = true
        receiveProgress = ShareProgress(phase: .preparing, current: 0, total: 1, currentFileName: nil)

        let client = clientFactory()
        self.client = client

        let sessionInfo: ShareSessionInfo
        let songs: [ShareSongSummary]
        let playlists: [SharePlaylistSummary]
        do {
            sessionInfo = try await client.connect(to: qrContent)
            songs = try await client.fetchSongList()
            playlists = try await client.fetchPlaylistList()
        } catch {
            client.disconnect()
            self.client = nil
            isReceiving = false
            receiveProgress = nil
            throw error
        }

        await buildSongIndex()

        var newSongs: [ShareSongSummary] = []
        var exactMatchSongs: [ShareSongSummary] = []
        var fuzzyMatchSongs: [ShareSongSummary] = []
        for song in songs {
            let match = matchSong(title: song.title, artist: song.artist, album: song.album, duration: song.duration)
            switch match {
            case .exactMatch:
                exactMatchSongs.append(song)
            case .fuzzyMatch:
                fuzzyMatchSongs.append(song)
            case .noMatch:
                newSongs.append(song)
            }
        }

        var playlistLocalSongs: [String: Int] = [:]
        let fetchedPlaylists: [(String, [ShareSongSummary])] = try await withThrowingTaskGroup(
            of: (String, [ShareSongSummary]).self
        ) { group in
            for playlist in playlists {
                group.addTask {
                    let songs = try await client.fetchPlaylistSongs(at: playlist.index)
                    return (playlist.name, songs)
                }
            }
            var results: [(String, [ShareSongSummary])] = []
            for try await item in group { results.append(item) }
            return results
        }
        for (name, playlistSongs) in fetchedPlaylists {
            var localCount = 0
            for ps in playlistSongs {
                let match = matchSong(title: ps.title, artist: ps.artist, album: ps.album, duration: ps.duration)
                if case .noMatch = match { } else { localCount += 1 }
            }
            if localCount > 0 {
                playlistLocalSongs[name] = localCount
            }
        }

        let downloadSize = newSongs.reduce(Int64(0)) { $0 + $1.fileSize }

        let availableBytes = availableDiskSpace()
        let diskInsufficient = downloadSize > availableBytes
        if diskInsufficient {
            log.info("[Share] 磁盘空间不足: 需要 \(downloadSize), 可用 \(availableBytes)")
        }

        let result = ShareAnalysis(
            sessionInfo: sessionInfo,
            songs: songs,
            playlists: playlists,
            newSongs: newSongs,
            exactMatchSongs: exactMatchSongs,
            fuzzyMatchSongs: fuzzyMatchSongs,
            playlistLocalSongs: playlistLocalSongs,
            estimatedDownloadSize: downloadSize,
            insufficientDiskSpace: diskInsufficient
        )
        analysis = result
        receiveProgress = nil
        log.info("[Share] 分析完成: 新歌曲=\(newSongs.count), 精确匹配=\(exactMatchSongs.count), 模糊匹配=\(fuzzyMatchSongs.count), 歌单=\(playlists.count)")
        return result
    }

    func executeReceive() async throws -> ShareTransferResult {
        guard let analysis, let client else {
            throw AppError.fileSystemError("分享会话未建立")
        }
        log.info("[Share] 开始接收传输")
        beginBackgroundTask()
        defer { endBackgroundTask() }

        isReceiving = true
        isReceiveCancelled = false
        var songsReceived = 0
        var songsSkipped = 0
        var playlistsCreated = 0
        var localSongsLinked = 0
        var failedCount = 0

        let tempDir = SandboxPathManager.syncExtractURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let newSongs = analysis.newSongs
        let total = newSongs.count
        var importedSongMap: [Int: UUID] = [:]

        for (i, song) in newSongs.enumerated() {
            guard !isReceiveCancelled else { break }
            receiveProgress = ShareProgress(
                phase: .transferring,
                current: i + 1,
                total: total,
                currentFileName: song.title
            )

            do {
                let audioURL = try await client.downloadAudio(at: song.index, to: tempDir) { _ in }
                let ext = audioURL.pathExtension.isEmpty ? "mp3" : audioURL.pathExtension
                let result = await importService.processAppleMusicFile(
                    tempURL: audioURL,
                    originalFilename: "\(song.title).\(ext)",
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    coverData: nil
                )

                switch result.status {
                case .success, .successIncompleteMetadata:
                    songsReceived += 1
                    if let importedSong = result.song {
                        importedSongMap[song.index] = importedSong.id
                        addToSongIndex(importedSong)
                        await importCover(client: client, song: song, importedSong: importedSong, tempDir: tempDir)
                        await importLyrics(client: client, song: song, importedSong: importedSong, tempDir: tempDir)
                    }
                case .skippedDuplicate:
                    songsSkipped += 1
                    if let existingSong = result.song {
                        importedSongMap[song.index] = existingSong.id
                    }
                default:
                    failedCount += 1
                }
            } catch {
                log.error(error, context: "[Share] 歌曲下载/导入失败: \(song.title)")
                failedCount += 1
            }
        }

        let playlists = analysis.playlists
        for (i, playlist) in playlists.enumerated() {
            guard !isReceiveCancelled else { break }
            receiveProgress = ShareProgress(
                phase: .importing,
                current: i + 1,
                total: playlists.count,
                currentFileName: playlist.name
            )

            do {
                let playlistName = generateUniqueName(playlist.name)
                let created = try await playlistService.createPlaylist(
                    name: playlistName,
                    description: playlist.description
                )

                if let groupName = playlist.groupName, !groupName.isEmpty {
                    await ensureGroupExists(named: groupName, forPlaylist: created.id)
                }

                let playlistSongs = try await client.fetchPlaylistSongs(at: playlist.index)
                var songIds: [UUID] = []

                for ps in playlistSongs {
                    if let mappedId = importedSongMap[ps.index] {
                        songIds.append(mappedId)
                    } else {
                        let match = matchSong(title: ps.title, artist: ps.artist, album: ps.album, duration: ps.duration)
                        switch match {
                        case .exactMatch(let local), .fuzzyMatch(let local):
                            songIds.append(local.id)
                            localSongsLinked += 1
                        case .noMatch:
                            break
                        }
                    }
                }

                if !songIds.isEmpty {
                    try await playlistService.addSongs(songIds, to: created.id)
                }
                playlistsCreated += 1
            } catch {
                log.error(error, context: "[Share] 歌单创建失败: \(playlist.name)")
                failedCount += 1
            }
        }

        if isReceiveCancelled {
            log.info("[Share] 接收已取消，跳过结果构造")
            throw AppError.fileSystemError("接收已取消")
        }

        let result = ShareTransferResult(
            songsReceived: songsReceived,
            songsSkipped: songsSkipped + analysis.skippedSongs.count,
            playlistsCreated: playlistsCreated,
            localSongsLinked: localSongsLinked,
            failedCount: failedCount
        )
        transferResult = result
        receiveProgress = ShareProgress(phase: .completed, current: total, total: total, currentFileName: nil)
        log.info("[Share] 接收完成: 新增=\(songsReceived), 跳过=\(result.songsSkipped), 歌单=\(playlistsCreated), 关联=\(localSongsLinked)")

        try? await client.notifyComplete(result: result)

        return result
    }

    func cancelReceive() {
        log.info("[Share] 取消接收")
        isReceiveCancelled = true
        client?.disconnect()
        client = nil
        isReceiving = false
        receiveProgress = nil
        analysis = nil
        transferResult = nil
        clearShareData()
        endBackgroundTask()
    }

    // MARK: - ShareDataSource

    func sessionInfo() -> ShareSessionInfo {
        let totalSize = sharedSongs.reduce(Int64(0)) { $0 + $1.fileSize }
        return ShareSessionInfo(
            deviceName: UIDevice.current.name,
            sessionToken: "",
            songCount: sharedSongs.count,
            playlistCount: sharedPlaylists.count,
            totalSize: totalSize
        )
    }

    func songSummaries() -> [ShareSongSummary] {
        sharedSongs.enumerated().map { index, song in
            ShareSongSummary(
                index: index,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                fileSize: song.fileSize,
                hasCover: song.coverImagePath != nil,
                hasLyrics: song.lyricsPath != nil
            )
        }
    }

    func playlistSummaries() -> [SharePlaylistSummary] {
        sharedPlaylists.enumerated().map { index, detail in
            let groupName: String?
            if let gid = detail.playlist.groupId {
                groupName = groupService.groupDetails.first(where: { $0.id == gid })?.name
            } else {
                groupName = nil
            }
            return SharePlaylistSummary(
                index: index,
                name: detail.playlist.name,
                description: detail.playlist.description,
                groupName: groupName,
                songCount: detail.songs.count
            )
        }
    }

    func audioFileURL(at index: Int) -> URL? {
        guard index >= 0 && index < sharedSongs.count else { return nil }
        let url = SandboxPathManager.musicFileURL(relativePath: sharedSongs[index].fileRelativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func coverFileURL(at index: Int) -> URL? {
        guard index >= 0 && index < sharedSongs.count,
              let coverPath = sharedSongs[index].coverImagePath else { return nil }
        let url = fileStorage.coverImagesDirectoryURL.appendingPathComponent(coverPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func lyricsFileURL(at index: Int) -> URL? {
        guard index >= 0 && index < sharedSongs.count,
              let lyricsPath = sharedSongs[index].lyricsPath else { return nil }
        let url = fileStorage.lyricsDirectoryURL.appendingPathComponent(lyricsPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func playlistSongs(at index: Int) -> [ShareSongSummary] {
        guard index >= 0 && index < sharedPlaylists.count else { return [] }
        let detail = sharedPlaylists[index]
        return detail.songs.compactMap { song in
            guard let idx = sharedSongIdToIndex[song.id] else { return nil }
            return ShareSongSummary(
                index: idx,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                fileSize: song.fileSize,
                hasCover: song.coverImagePath != nil,
                hasLyrics: song.lyricsPath != nil
            )
        }
    }

    func songExportData(at index: Int) -> SongExportData? {
        guard index >= 0 && index < sharedSongs.count else { return nil }
        let song = sharedSongs[index]
        let audioName = URL(fileURLWithPath: song.fileRelativePath).lastPathComponent
        return SongExportData(song: song, audioFileName: audioName, coverFileName: nil, lyricsFileName: nil)
    }

    // MARK: - 发送端索引

    private func rebuildSharedSongIndex() {
        sharedSongIdToIndex = Dictionary(uniqueKeysWithValues: sharedSongs.enumerated().map { ($1.id, $0) })
    }

    private func clearShareData() {
        sharedSongs = []
        sharedPlaylists = []
        sharedSongIdToIndex = [:]
        songIndex = [:]
    }

    // MARK: - 歌曲匹配

    private func buildSongIndex() async {
        let allSongs: [Song]
        do {
            allSongs = try await songRepo.fetchAll(sortBy: .title, ascending: true)
        } catch {
            log.error(error, context: "构建歌曲索引失败")
            allSongs = []
        }
        songIndex = Dictionary(grouping: allSongs) { Self.normalizedKey($0.title, $0.artist) }
    }

    private func addToSongIndex(_ song: Song) {
        let key = Self.normalizedKey(song.title, song.artist)
        songIndex[key, default: []].append(song)
    }

    private static func normalizedKey(_ title: String, _ artist: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(t)|\(a)"
    }

    private func matchSong(title: String, artist: String, album: String, duration: TimeInterval) -> SongMatchResult {
        let key = Self.normalizedKey(title, artist)
        guard let candidates = songIndex[key] else { return .noMatch }

        if let exact = candidates.first(where: {
            $0.album == album && abs($0.duration - duration) < 2.0
        }) {
            return .exactMatch(exact)
        }

        if let fuzzy = candidates.first {
            return .fuzzyMatch(fuzzy)
        }

        return .noMatch
    }

    // MARK: - Private

    private func startServer() async throws -> String {
        let server = serverFactory()
        server.dataSource = self
        let totalSongs = sharedSongs.count

        server.onAudioFileServed = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let served = (self.sendProgress?.current ?? 0) + 1
                self.sendProgress = ShareProgress(
                    phase: .transferring,
                    current: served,
                    total: totalSongs,
                    currentFileName: "已传输 \(served)/\(totalSongs)"
                )
            }
        }

        server.onDeviceConnected = { [weak self] device in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connectedReceiver = device
            }
        }

        server.onTransferCompleted = { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let totalTransferred = result.songsReceived + result.songsSkipped
                self.sendProgress = ShareProgress(
                    phase: .completed,
                    current: totalTransferred,
                    total: totalTransferred,
                    currentFileName: "传输完成"
                )
            }
        }

        server.onReceiverDisconnected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .completed = self.sendProgress?.phase { return }
                self.log.info("[Share] 接收端断开连接")
                let served = self.sendProgress?.current ?? 0
                self.sendProgress = ShareProgress(
                    phase: .failed("接收端已断开"),
                    current: served,
                    total: served,
                    currentFileName: nil
                )
            }
        }

        try await server.start()
        self.server = server
        isSending = true
        sendProgress = ShareProgress(phase: .preparing, current: 0, total: totalSongs, currentFileName: "等待接收方连接…")

        guard let qr = server.qrCodeContent else {
            throw AppError.fileSystemError("无法获取服务器地址")
        }
        return qr
    }

    private func importCover(client: ShareClientProviding, song: ShareSongSummary, importedSong: Song, tempDir: URL) async {
        guard song.hasCover else { return }
        do {
            if let coverURL = try await client.downloadCover(at: song.index, to: tempDir) {
                let coverName = "\(importedSong.id.uuidString)_medium.jpg"
                let destURL = fileStorage.coverImagesDirectoryURL.appendingPathComponent(coverName)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.copyItem(at: coverURL, to: destURL)
                if importedSong.coverImagePath == nil {
                    try? await songRepo.updateCoverPath(songId: importedSong.id, coverImagePath: coverName)
                }
            }
        } catch {
            log.error(error, context: "[Share] 封面下载失败: \(song.title)")
        }
    }

    private func importLyrics(client: ShareClientProviding, song: ShareSongSummary, importedSong: Song, tempDir: URL) async {
        guard song.hasLyrics else { return }
        do {
            if let lyricsURL = try await client.downloadLyrics(at: song.index, to: tempDir) {
                let ext = lyricsURL.pathExtension.isEmpty ? "lrc" : lyricsURL.pathExtension
                let destName = "\(importedSong.id.uuidString).\(ext)"
                let destURL = fileStorage.lyricsDirectoryURL.appendingPathComponent(destName)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.copyItem(at: lyricsURL, to: destURL)
                try? await songRepo.updateLyrics(songId: importedSong.id, lyricsPath: destName, lyricsSource: .file)
            }
        } catch {
            log.error(error, context: "[Share] 歌词下载失败: \(song.title)")
        }
    }

    private func generateUniqueName(_ baseName: String) -> String {
        let existing = playlistService.playlists.map { $0.name }
        var candidate = baseName
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(baseName)-\(counter)"
            counter += 1
        }
        return candidate
    }

    private func ensureGroupExists(named name: String, forPlaylist playlistId: UUID) async {
        await groupService.loadGroups()
        let details = groupService.groupDetails

        if let existing = details.first(where: { $0.name == name }) {
            try? await groupService.movePlaylist(playlistId, toGroup: existing.id)
        } else {
            if let newGroup = try? await groupService.createGroup(name: name) {
                try? await groupService.movePlaylist(playlistId, toGroup: newGroup.id)
            }
        }
    }

    private func availableDiskSpace() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        )
        return (attrs?[.systemFreeSize] as? Int64) ?? Int64.max
    }

    private func beginBackgroundTask() {
        backgroundTaskID = backgroundTask.beginTask { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != 0 else { return }
        backgroundTask.endTask(backgroundTaskID)
        backgroundTaskID = 0
    }
}

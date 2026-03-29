import Foundation

@MainActor
final class SyncImportService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var isImporting = false
    @Published private(set) var progress: SyncProgress?
    @Published var songConflicts: [SongConflict] = []
    @Published var playlistConflicts: [PlaylistConflict] = []

    private let songRepo: SongRepository
    private let playlistService: PlaylistService
    private let groupService: PlaylistGroupService
    private let importService: ImportService
    private let syncRepo: SyncRepository
    private let packager: SyncPackaging
    private let fileStorage: FileStorageProviding

    private var songIndex: [String: [Song]] = [:]

    init(songRepo: SongRepository,
         playlistService: PlaylistService,
         groupService: PlaylistGroupService,
         importService: ImportService,
         syncRepo: SyncRepository,
         packager: SyncPackaging,
         fileStorage: FileStorageProviding) {
        self.songRepo = songRepo
        self.playlistService = playlistService
        self.groupService = groupService
        self.importService = importService
        self.syncRepo = syncRepo
        self.packager = packager
        self.fileStorage = fileStorage
    }

    // MARK: - 分析

    func analyze(fileURL: URL) async throws -> SyncAnalysisResult {
        log.info("开始分析同步包: \(fileURL.lastPathComponent)")
        isImporting = true
        progress = SyncProgress(phase: .preparing, current: 0, total: 1, currentFileName: nil)

        let (manifest, extractedDir) = try await packager.unpack(fileURL: fileURL) { [weak self] p in
            Task { @MainActor in self?.progress = p }
        }

        await buildSongIndex()

        var sConflicts: [SongConflict] = []
        var newSongs = 0
        if let songs = manifest.songs {
            for exportSong in songs {
                let match = matchSong(exportSong)
                switch match {
                case .exactMatch(let existing), .fuzzyMatch(let existing):
                    sConflicts.append(SongConflict(incoming: exportSong, existing: existing))
                case .noMatch:
                    newSongs += 1
                }
            }
        }

        var pConflicts: [PlaylistConflict] = []
        var newPlaylists = 0
        if let playlists = manifest.playlists {
            await playlistService.loadPlaylists()
            let existingPlaylists = playlistService.playlists.filter { !$0.isSystem }
            for exportPlaylist in playlists {
                if let existing = existingPlaylists.first(where: { $0.name == exportPlaylist.name }) {
                    pConflicts.append(PlaylistConflict(incoming: exportPlaylist, existing: existing))
                } else {
                    newPlaylists += 1
                }
            }
        }

        songConflicts = sConflicts
        playlistConflicts = pConflicts

        let importSize = estimateImportSize(manifest: manifest, extractedDir: extractedDir)

        isImporting = false
        progress = nil
        log.info("分析完成: 新歌曲=\(newSongs), 歌曲冲突=\(sConflicts.count), 新歌单=\(newPlaylists), 歌单冲突=\(pConflicts.count)")

        return SyncAnalysisResult(
            manifest: manifest,
            extractedDir: extractedDir,
            songConflicts: sConflicts,
            playlistConflicts: pConflicts,
            newSongsCount: newSongs,
            newPlaylistsCount: newPlaylists,
            estimatedImportSize: importSize
        )
    }

    // MARK: - 执行导入

    func executeImport(
        analysisResult: SyncAnalysisResult,
        songResolution: SongConflictResolution?,
        playlistResolution: PlaylistConflictResolution?
    ) async throws -> SyncImportResult {
        log.info("开始执行同步导入")
        isImporting = true
        defer { isImporting = false; progress = nil }

        var songsImported = 0
        var songsSkipped = 0
        var songsFailed = 0
        var playlistsImported = 0
        var playlistsSkipped = 0
        var missingSongsCount = 0

        let manifest = analysisResult.manifest
        let extractedDir = analysisResult.extractedDir

        if let songs = manifest.songs,
           manifest.contentType == .songs || manifest.contentType == .playlistsWithAudio {
            let total = songs.count
            for (i, exportSong) in songs.enumerated() {
                progress = SyncProgress(phase: .importing, current: i + 1, total: total, currentFileName: exportSong.title)

                let match = matchSong(exportSong)
                let resolution: SongConflictResolution

                switch match {
                case .exactMatch, .fuzzyMatch:
                    if let perSong = songConflicts.first(where: {
                        $0.incoming == exportSong
                    })?.resolution {
                        resolution = perSong
                    } else if let global = songResolution {
                        resolution = global
                    } else {
                        resolution = .skip
                    }
                case .noMatch:
                    resolution = .replace
                }

                switch resolution {
                case .skip:
                    songsSkipped += 1
                case .replace, .saveAsCopy:
                    let audioURL = extractedDir.appendingPathComponent(exportSong.audioFileName)
                    guard FileManager.default.fileExists(atPath: audioURL.path) else {
                        songsFailed += 1
                        continue
                    }
                    let result = await importService.processWiFiFile(
                        tempURL: audioURL,
                        originalFilename: (exportSong.audioFileName as NSString).lastPathComponent
                    )
                    switch result.status {
                    case .success, .successIncompleteMetadata:
                        songsImported += 1
                        if let song = result.song {
                            await importCover(for: song, exportData: exportSong, extractedDir: extractedDir)
                            await importLyrics(for: song, exportData: exportSong, extractedDir: extractedDir)
                        }
                        if resolution == .replace {
                            await deleteOldMatchedSong(match: match, newSongId: result.song?.id)
                        }
                    case .skippedDuplicate:
                        if resolution == .replace, let existingSong = result.song {
                            await importCover(for: existingSong, exportData: exportSong, extractedDir: extractedDir)
                            await importLyrics(for: existingSong, exportData: exportSong, extractedDir: extractedDir)
                            songsImported += 1
                        } else {
                            songsSkipped += 1
                        }
                    default:
                        songsFailed += 1
                    }
                }
            }
        }

        if let playlists = manifest.playlists {
            let total = playlists.count
            for (i, exportPlaylist) in playlists.enumerated() {
                progress = SyncProgress(phase: .importing, current: i + 1, total: total, currentFileName: exportPlaylist.name)

                let existingMatch = playlistConflicts.first(where: { $0.incoming.name == exportPlaylist.name })
                let resolution: PlaylistConflictResolution

                if let perPlaylist = existingMatch?.resolution {
                    resolution = perPlaylist
                } else if let global = playlistResolution, existingMatch != nil {
                    resolution = global
                } else if existingMatch != nil {
                    resolution = .merge
                } else {
                    resolution = .createCopy
                }

                do {
                    let playlistId: UUID
                    switch resolution {
                    case .replace:
                        guard let existing = existingMatch?.existing else {
                            playlistsSkipped += 1
                            continue
                        }
                        playlistId = existing.id
                        let detail = await playlistService.fetchDetail(playlistId: playlistId)
                        if let detail {
                            let existingSongIds = detail.songs.map { $0.id }
                            if !existingSongIds.isEmpty {
                                try await playlistService.removeSongs(existingSongIds, from: playlistId)
                            }
                        }
                        try await playlistService.updatePlaylist(
                            id: playlistId,
                            name: exportPlaylist.name,
                            description: exportPlaylist.description
                        )
                        try await syncRepo.deleteMissingReferences(forPlaylist: playlistId)

                    case .merge:
                        guard let existing = existingMatch?.existing else {
                            playlistsSkipped += 1
                            continue
                        }
                        playlistId = existing.id

                    case .createCopy:
                        let name: String
                        if existingMatch != nil {
                            name = generateUniqueName(exportPlaylist.name)
                        } else {
                            name = exportPlaylist.name
                        }
                        let created = try await playlistService.createPlaylist(
                            name: name,
                            description: exportPlaylist.description
                        )
                        playlistId = created.id
                    }

                    if let groupName = exportPlaylist.groupName, !groupName.isEmpty {
                        await ensureGroupExists(named: groupName, forPlaylist: playlistId)
                    }

                    let (matched, missing) = await matchPlaylistSongs(exportPlaylist.songs, playlistId: playlistId)

                    if !matched.isEmpty {
                        if resolution == .merge {
                            let detail = await playlistService.fetchDetail(playlistId: playlistId)
                            let existingIds = Set(detail?.songs.map { $0.id } ?? [])
                            let newIds = matched.filter { !existingIds.contains($0) }
                            if !newIds.isEmpty {
                                try await playlistService.addSongs(newIds, to: playlistId)
                            }
                        } else {
                            try await playlistService.addSongs(matched, to: playlistId)
                        }
                    }

                    if !missing.isEmpty {
                        try await syncRepo.insertMissingReferences(missing)
                        missingSongsCount += missing.count
                    }

                    playlistsImported += 1
                } catch {
                    log.error(error, context: "歌单导入失败: \(exportPlaylist.name)")
                    playlistsSkipped += 1
                }
            }
        }

        await buildSongIndex()

        let result = SyncImportResult(
            songsImported: songsImported,
            songsSkipped: songsSkipped,
            songsFailed: songsFailed,
            playlistsImported: playlistsImported,
            playlistsSkipped: playlistsSkipped,
            missingSongsCount: missingSongsCount
        )
        log.info("导入完成: 歌曲导入=\(songsImported) 跳过=\(songsSkipped) 失败=\(songsFailed) 歌单=\(playlistsImported) 缺失=\(missingSongsCount)")
        return result
    }

    // MARK: - 缺失歌曲恢复

    func checkAndRecoverMissingSongs() async {
        let allRefs = await syncRepo.fetchAllMissingReferences()
        guard !allRefs.isEmpty else { return }

        await buildSongIndex()
        var recoveredIds: [UUID] = []

        for ref in allRefs {
            let exportData = SongExportData(
                title: ref.title,
                artist: ref.artist,
                album: ref.album,
                duration: ref.duration,
                format: "",
                sampleRate: nil,
                bitRate: nil,
                channels: nil,
                trackNumber: nil,
                year: nil,
                genre: nil,
                audioFileName: "",
                coverFileName: nil,
                lyricsFileName: nil
            )
            let match = matchSong(exportData)
            switch match {
            case .exactMatch(let song), .fuzzyMatch(let song):
                do {
                    try await playlistService.addSongs([song.id], to: ref.playlistId)
                    recoveredIds.append(ref.id)
                    log.info("缺失歌曲已恢复: \(ref.title) → 歌单 \(ref.playlistId)")
                } catch {
                    log.error(error, context: "缺失歌曲恢复失败: \(ref.title)")
                }
            case .noMatch:
                break
            }
        }

        if !recoveredIds.isEmpty {
            try? await syncRepo.deleteMissingReferences(ids: recoveredIds)
            log.info("共恢复 \(recoveredIds.count) 首缺失歌曲")
        }
    }

    // MARK: - 匹配引擎

    private func buildSongIndex() async {
        let allSongs = await songRepo.fetchAll(sortBy: .title, ascending: true)
        songIndex = Dictionary(grouping: allSongs) { "\($0.title)|\($0.artist)" }
    }

    private func matchSong(_ exportData: SongExportData) -> SongMatchResult {
        let key = "\(exportData.title)|\(exportData.artist)"
        guard let candidates = songIndex[key] else { return .noMatch }

        if let exact = candidates.first(where: {
            $0.album == exportData.album &&
            abs($0.duration - exportData.duration) < 2.0
        }) {
            return .exactMatch(exact)
        }

        if let fuzzy = candidates.first {
            return .fuzzyMatch(fuzzy)
        }

        return .noMatch
    }

    // MARK: - 辅助方法

    private func matchPlaylistSongs(
        _ songs: [SongExportData],
        playlistId: UUID
    ) async -> (matchedIds: [UUID], missing: [MissingSongReference]) {
        var matchedIds: [UUID] = []
        var missing: [MissingSongReference] = []

        for exportSong in songs {
            let match = matchSong(exportSong)
            switch match {
            case .exactMatch(let song), .fuzzyMatch(let song):
                matchedIds.append(song.id)
            case .noMatch:
                missing.append(MissingSongReference(
                    title: exportSong.title,
                    artist: exportSong.artist,
                    album: exportSong.album,
                    duration: exportSong.duration,
                    playlistId: playlistId
                ))
            }
        }

        return (matchedIds, missing)
    }

    private func importCover(for song: Song, exportData: SongExportData, extractedDir: URL) async {
        guard let coverFile = exportData.coverFileName else { return }
        let coverURL = extractedDir.appendingPathComponent(coverFile)
        let fm = FileManager.default
        guard fm.fileExists(atPath: coverURL.path) else { return }

        let destURL = fileStorage.coverImagesDirectoryURL
            .appendingPathComponent("\(song.id.uuidString)_medium.jpg")
        try? fm.removeItem(at: destURL)
        try? fm.copyItem(at: coverURL, to: destURL)
    }

    private func importLyrics(for song: Song, exportData: SongExportData, extractedDir: URL) async {
        guard let lyricsFile = exportData.lyricsFileName else { return }
        let lyricsURL = extractedDir.appendingPathComponent(lyricsFile)
        let fm = FileManager.default
        guard fm.fileExists(atPath: lyricsURL.path) else { return }

        let ext = (lyricsFile as NSString).pathExtension
        let destName = "\(song.id.uuidString).\(ext.isEmpty ? "lrc" : ext)"
        let destURL = fileStorage.lyricsDirectoryURL.appendingPathComponent(destName)
        try? fm.removeItem(at: destURL)
        try? fm.copyItem(at: lyricsURL, to: destURL)

        try? await songRepo.updateLyrics(songId: song.id, lyricsPath: destName, lyricsSource: .file)
    }

    private func deleteOldMatchedSong(match: SongMatchResult, newSongId: UUID?) async {
        let existingId: UUID?
        switch match {
        case .exactMatch(let song), .fuzzyMatch(let song): existingId = song.id
        case .noMatch: existingId = nil
        }
        guard let existingId, existingId != newSongId else { return }
        do {
            let token = try await songRepo.softDelete(ids: [existingId])
            try await songRepo.commitDelete(token: token)
        } catch {
            log.error(error, context: "替换旧歌曲失败: \(existingId)")
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

    private func estimateImportSize(manifest: TuneHavenManifest, extractedDir: URL) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: extractedDir, includingPropertiesForKeys: [.fileSizeKey]) {
            while let url = enumerator.nextObject() as? URL {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += Int64(size)
            }
        }
        return total
    }
}

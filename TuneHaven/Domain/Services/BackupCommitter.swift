import Foundation

struct BackupPreparedFiles: Sendable {
    var snapshot: BackupLibrarySnapshot
    var created: [URL]
}

enum BackupCommitter {
    /// 把包内文件复制到尚不存在的新路径。失败或取消时删掉本次新建的文件，不调用 `apply`。
    static func prepareFiles(
        plan: BackupCommitPlan,
        packageRoot: URL,
        layout: BackupFileLayout,
        isCancelled: () -> Bool
    ) throws -> BackupPreparedFiles {
        let fileManager = FileManager.default
        var created: [URL] = []
        var songs = plan.snapshot.songs
        do {
            for copy in plan.copies {
                if isCancelled() { throw AppError.backupCancelled }
                let source = packageRoot.appendingPathComponent(copy.sourceEntry)
                guard fileManager.fileExists(atPath: source.path) else {
                    clearMissing(&songs, copy: copy)
                    continue
                }
                let desired = layout.url(for: copy.destination)
                let destination = try place(from: source, desired: desired, created: &created)
                applyPlacedFile(destination, copy: copy, songs: &songs, layout: layout)
            }
            if isCancelled() { throw AppError.backupCancelled }
        } catch {
            rollback(created)
            throw error
        }
        var snapshot = plan.snapshot
        snapshot.songs = songs
        return BackupPreparedFiles(snapshot: snapshot, created: created)
    }

    static func commit(
        original: BackupLibrarySnapshot,
        plan: BackupCommitPlan,
        packageRoot: URL,
        layout: BackupFileLayout,
        library: BackupLibraryApplying,
        isCancelled: () -> Bool
    ) async throws -> BackupRestoreSummary {
        let prepared = try prepareFiles(
            plan: plan,
            packageRoot: packageRoot,
            layout: layout,
            isCancelled: isCancelled
        )
        if isCancelled() {
            rollback(prepared.created)
            throw AppError.backupCancelled
        }
        do {
            try await library.apply(prepared.snapshot)
        } catch {
            rollback(prepared.created)
            if let appError = error as? AppError {
                throw appError
            }
            throw AppError.backupCommitRolledBack("曲库没有被修改")
        }
        removeObsoleteFiles(from: original, to: prepared.snapshot, layout: layout)
        return plan.summary
    }

    static func rollback(_ urls: [URL]) {
        for url in urls.reversed() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Files

    private static func place(from source: URL, desired: URL, created: inout [URL]) throws -> URL {
        let fileManager = FileManager.default
        let destination = uniqueURL(desired)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
        created.append(destination)
        return destination
    }

    private static func uniqueURL(_ desired: URL) -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: desired.path) { return desired }
        let directory = desired.deletingLastPathComponent()
        let ext = desired.pathExtension
        let base = desired.deletingPathExtension().lastPathComponent
        for index in 2...999 {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        let fallback = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        return directory.appendingPathComponent(fallback)
    }

    private static func applyPlacedFile(
        _ url: URL,
        copy: BackupPlannedCopy,
        songs: inout [BackupLibrarySong],
        layout: BackupFileLayout
    ) {
        guard let index = songs.firstIndex(where: { $0.id == copy.librarySongId }) else { return }
        let song = songs[index].song
        switch copy.destination {
        case .music:
            let relative = layout.relativePath(of: url, under: layout.musicDirectory)
            songs[index].song = song.withStoredMedia(
                fileRelativePath: relative,
                coverImagePath: song.coverImagePath,
                lyricsPath: song.lyricsPath
            )
        case .cover:
            songs[index].song = song.withStoredMedia(
                fileRelativePath: song.fileRelativePath,
                coverImagePath: url.lastPathComponent,
                lyricsPath: song.lyricsPath
            )
        case .lyrics:
            let relative = layout.relativePath(of: url, under: layout.lyricsDirectory)
            songs[index].song = song.withStoredMedia(
                fileRelativePath: song.fileRelativePath,
                coverImagePath: song.coverImagePath,
                lyricsPath: relative,
                lyricsSource: copy.lyricsSource ?? .file,
                updateLyricsSource: true
            )
        }
    }

    private static func clearMissing(_ songs: inout [BackupLibrarySong], copy: BackupPlannedCopy) {
        guard let index = songs.firstIndex(where: { $0.id == copy.librarySongId }) else { return }
        let song = songs[index].song
        switch copy.destination {
        case .music:
            songs[index].song = song.withStoredMedia(
                fileRelativePath: Song.missingAudioPath(for: song.id),
                coverImagePath: song.coverImagePath,
                lyricsPath: song.lyricsPath
            )
        case .cover, .lyrics:
            break
        }
    }

    private static func removeObsoleteFiles(
        from original: BackupLibrarySnapshot,
        to committed: BackupLibrarySnapshot,
        layout: BackupFileLayout
    ) {
        let oldSongs = original.songs.map(\.song)
        let newSongs = committed.songs.map(\.song)
        let newMusic = Set(newSongs.map(\.fileRelativePath))
        let newLyrics = Set(newSongs.compactMap(\.lyricsPath))
        let newCovers = Set(newSongs.compactMap(\.coverImagePath))
        let fileManager = FileManager.default
        for song in oldSongs where !song.isAudioMissing && !newMusic.contains(song.fileRelativePath) {
            let url = layout.url(for: .music(relativePath: song.fileRelativePath))
            try? fileManager.removeItem(at: url)
        }
        for path in Set(oldSongs.compactMap(\.lyricsPath)) where !newLyrics.contains(path) {
            try? fileManager.removeItem(at: layout.url(for: .lyrics(relativePath: path)))
        }
        for key in Set(oldSongs.compactMap(\.coverImagePath)) where !newCovers.contains(key) {
            try? fileManager.removeItem(at: layout.url(for: .cover(key: key)))
        }
    }
}

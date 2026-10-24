import Foundation

enum BackupExporter {
    static func estimate(snapshot: BackupLibrarySnapshot, includeAudio: Bool, layout: BackupFileLayout) -> Int64 {
        makePackage(
            snapshot: snapshot,
            includeAudio: includeAudio,
            appVersion: "0",
            exportedAt: Date(),
            layout: layout
        ).files.reduce(2048) { $0 + $1.byteCount }
    }

    static func makePackage(
        snapshot: BackupLibrarySnapshot,
        includeAudio: Bool,
        appVersion: String,
        exportedAt: Date,
        layout: BackupFileLayout
    ) -> BackupExportDraft {
        let fileManager = FileManager.default
        var songs: [BackupSongRecord] = []
        var files: [BackupExportFile] = []
        songs.reserveCapacity(snapshot.songs.count)

        for item in snapshot.songs {
            let song = item.song
            var audioEntry: String?
            if includeAudio, !song.isAudioMissing {
                let source = layout.url(for: .music(relativePath: song.fileRelativePath))
                if fileManager.fileExists(atPath: source.path) {
                    let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension.lowercased()
                    let entry = "\(BackupPackageFormat.audioDirectory)/\(song.id.uuidString).\(ext)"
                    audioEntry = entry
                    files.append(BackupExportFile(sourceURL: source, entryPath: entry, byteCount: fileSize(source)))
                }
            }
            var coverEntry: String?
            if let key = song.coverImagePath, !key.isEmpty {
                let source = layout.url(for: .cover(key: key))
                if fileManager.fileExists(atPath: source.path) {
                    let entry = "\(BackupPackageFormat.coverDirectory)/\(song.id.uuidString).jpg"
                    coverEntry = entry
                    files.append(BackupExportFile(sourceURL: source, entryPath: entry, byteCount: fileSize(source)))
                }
            }
            var lyricsEntry: String?
            if let relative = song.lyricsPath, !relative.isEmpty {
                let source = layout.url(for: .lyrics(relativePath: relative))
                if fileManager.fileExists(atPath: source.path) {
                    let entry = "\(BackupPackageFormat.lyricsDirectory)/\(song.id.uuidString).lrc"
                    lyricsEntry = entry
                    files.append(BackupExportFile(sourceURL: source, entryPath: entry, byteCount: fileSize(source)))
                }
            }
            songs.append(BackupSongRecord(
                id: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                fileHash: song.fileHash,
                fileSize: song.fileSize,
                format: song.metadata.format,
                sampleRate: song.metadata.sampleRate,
                bitRate: song.metadata.bitRate,
                channels: song.metadata.channels,
                encoder: song.metadata.encoder,
                trackNumber: song.metadata.trackNumber,
                year: song.metadata.year,
                genre: song.metadata.genre,
                audioEntry: audioEntry,
                coverEntry: coverEntry,
                lyricsEntry: lyricsEntry,
                lyricsSource: song.lyricsSource.map { Int($0.rawValue) },
                isFavorite: song.isFavorite,
                favoriteDate: song.favoriteDate,
                importDate: song.importDate
            ))
        }

        let groupNames = Dictionary(snapshot.groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let playlists = snapshot.playlists
            .filter { !$0.isSystem && $0.systemTypeRaw == SystemPlaylistType.normal.rawValue }
            .map { playlist in
                BackupPlaylistRecord(
                    id: playlist.id,
                    name: playlist.name,
                    description: playlist.description,
                    groupName: playlist.groupId.flatMap { groupNames[$0] },
                    sortOrder: playlist.sortOrder,
                    songIds: playlist.songIds
                )
            }
        let groups = snapshot.groups.map {
            BackupGroupRecord(id: $0.id, name: $0.name, sortOrder: $0.sortOrder)
        }
        let payload = files.reduce(Int64(0)) { $0 + $1.byteCount }
        let manifest = BackupManifest(
            formatVersion: BackupPackageFormat.version,
            appVersion: appVersion,
            exportedAt: exportedAt,
            includesAudio: songs.contains { $0.audioEntry != nil },
            songCount: songs.count,
            playlistCount: playlists.count,
            groupCount: groups.count,
            payloadBytes: payload
        )
        let catalog = BackupCatalog(
            manifest: manifest,
            preferences: snapshot.preferences,
            groups: groups,
            playlists: playlists,
            songs: songs
        )
        return BackupExportDraft(catalog: catalog, files: files)
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let raw = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] else { return 0 }
        if let number = raw as? NSNumber { return number.int64Value }
        if let value = raw as? Int64 { return value }
        return 0
    }
}

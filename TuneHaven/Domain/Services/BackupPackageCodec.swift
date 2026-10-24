import Foundation

enum BackupPackageCodec {
    static func write(
        draft: BackupExportDraft,
        to zipURL: URL,
        stagingParent: URL,
        isCancelled: () -> Bool = { false }
    ) throws {
        if isCancelled() { throw AppError.backupCancelled }
        let fileManager = FileManager.default
        if draft.catalog.manifest.payloadBytes > Int64(BackupPackageFormat.maxZipOffset) {
            throw AppError.backupInvalidPackage("备份超过 4GB，请关闭「包含音频」后重试")
        }
        let staging = stagingParent.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let encoder = BackupJSON.encoder()
        try encoder.encode(draft.catalog.manifest).write(to: staging.appendingPathComponent(BackupPackageFormat.manifestFile))
        try encoder.encode(draft.catalog.preferences).write(to: staging.appendingPathComponent(BackupPackageFormat.preferencesFile))
        try encoder.encode(draft.catalog.groups).write(to: staging.appendingPathComponent(BackupPackageFormat.groupsFile))
        try encoder.encode(draft.catalog.playlists).write(to: staging.appendingPathComponent(BackupPackageFormat.playlistsFile))
        try encoder.encode(draft.catalog.songs).write(to: staging.appendingPathComponent(BackupPackageFormat.songsFile))
        for file in draft.files {
            try ZipStoreArchive.validateEntryName(file.entryPath)
            let destination = staging.appendingPathComponent(file.entryPath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: file.sourceURL, to: destination)
        }
        try fileManager.createDirectory(at: zipURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try ZipStoreArchive.zipDirectory(at: staging, to: zipURL, isCancelled: isCancelled)
        } catch {
            try? fileManager.removeItem(at: zipURL)
            throw error
        }
    }

    static func extract(zipURL: URL, to destination: URL) throws -> BackupCatalog {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try ZipStoreArchive.unzip(zipURL, to: destination)
            return try readCatalog(at: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    static func readCatalog(at root: URL) throws -> BackupCatalog {
        let decoder = BackupJSON.decoder()
        let manifest = try decode(BackupManifest.self, file: BackupPackageFormat.manifestFile, root: root, decoder: decoder)
        guard manifest.formatVersion == BackupPackageFormat.version else {
            throw AppError.backupUnsupportedVersion(manifest.formatVersion)
        }
        let preferences = try decode(BackupPreferences.self, file: BackupPackageFormat.preferencesFile, root: root, decoder: decoder)
        let groups = try decode([BackupGroupRecord].self, file: BackupPackageFormat.groupsFile, root: root, decoder: decoder)
        let playlists = try decode([BackupPlaylistRecord].self, file: BackupPackageFormat.playlistsFile, root: root, decoder: decoder)
        var songs = try decode([BackupSongRecord].self, file: BackupPackageFormat.songsFile, root: root, decoder: decoder)
        let fileManager = FileManager.default
        for index in songs.indices {
            if let entry = songs[index].audioEntry {
                try ZipStoreArchive.validateEntryName(entry)
                let url = root.appendingPathComponent(entry)
                if !fileManager.fileExists(atPath: url.path) {
                    songs[index].audioEntry = nil
                }
            }
            if let entry = songs[index].coverEntry {
                try ZipStoreArchive.validateEntryName(entry)
                if !fileManager.fileExists(atPath: root.appendingPathComponent(entry).path) {
                    songs[index].coverEntry = nil
                }
            }
            if let entry = songs[index].lyricsEntry {
                try ZipStoreArchive.validateEntryName(entry)
                if !fileManager.fileExists(atPath: root.appendingPathComponent(entry).path) {
                    songs[index].lyricsEntry = nil
                }
            }
        }
        return BackupCatalog(
            manifest: manifest,
            preferences: preferences,
            groups: groups,
            playlists: playlists,
            songs: songs
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, file: String, root: URL, decoder: JSONDecoder) throws -> T {
        let url = root.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.backupInvalidPackage("缺少 \(file)")
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.backupInvalidPackage("无法读取 \(file)")
        }
    }
}

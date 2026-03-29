import Foundation
import UIKit

/// .tunehaven 文件格式编解码器
///
/// 文件格式（流式二进制，音频已压缩无需再压缩）：
/// ```
/// [8 bytes: magic "TUNEHVN\0"]
/// [4 bytes: version, UInt32 LE]
/// [4 bytes: manifest JSON length, UInt32 LE]
/// [manifest JSON bytes]
/// [4 bytes: file entry count, UInt32 LE]
/// For each entry:
///   [2 bytes: relative path length, UInt16 LE]
///   [path UTF-8 bytes]
///   [8 bytes: data length, UInt64 LE]
///   [data bytes]
/// ```
final class TuneHavenPackager: SyncPackaging {

    private static let magic: [UInt8] = [0x54, 0x55, 0x4E, 0x45, 0x48, 0x56, 0x4E, 0x00] // "TUNEHVN\0"
    private static let currentVersion: UInt32 = 1
    private static let streamChunkSize = 1024 * 1024 // 1 MB

    private let fm = FileManager.default

    // MARK: - SyncPackaging

    func export(
        songs: [Song],
        playlists: [PlaylistDetail],
        includeAudioFiles: Bool,
        groupNames: [UUID: String],
        progressHandler: @escaping (SyncProgress) -> Void
    ) async throws -> URL {
        let exportDir = SandboxPathManager.exportTempURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let contentType: SyncContentType
        if !playlists.isEmpty {
            contentType = includeAudioFiles ? .playlistsWithAudio : .playlists
        } else {
            contentType = .songs
        }

        var fileEntries: [(relativePath: String, sourceURL: URL)] = []
        var songExportList: [SongExportData] = []
        var playlistExportList: [PlaylistExportData] = []

        let allSongsToExport: [Song]
        if !songs.isEmpty {
            allSongsToExport = songs
        } else if includeAudioFiles {
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
            allSongsToExport = unique
        } else {
            allSongsToExport = []
        }

        let totalSteps = allSongsToExport.count + playlists.count + 1
        var currentStep = 0

        for (index, song) in allSongsToExport.enumerated() {
            let prefix = String(format: "%04d", index + 1)
            let audioName = "\(prefix)_\(sanitize(song.fileRelativePath))"
            let audioSource = SandboxPathManager.musicFileURL(relativePath: song.fileRelativePath)
            guard fm.fileExists(atPath: audioSource.path) else { continue }
            fileEntries.append(("songs/\(audioName)", audioSource))

            var coverName: String?
            if let coverPath = song.coverImagePath {
                let coverSource = SandboxPathManager.coverImagesURL
                    .appendingPathComponent(coverPath)
                if fm.fileExists(atPath: coverSource.path) {
                    coverName = "covers/\(prefix)_cover.jpg"
                    fileEntries.append((coverName!, coverSource))
                }
            }

            var lyricsName: String?
            if let lyricsPath = song.lyricsPath {
                let lyricsSource = SandboxPathManager.lyricsFileURL(relativePath: lyricsPath)
                if fm.fileExists(atPath: lyricsSource.path) {
                    let ext = (lyricsPath as NSString).pathExtension
                    lyricsName = "lyrics/\(prefix)_lyrics.\(ext.isEmpty ? "lrc" : ext)"
                    fileEntries.append((lyricsName!, lyricsSource))
                }
            }

            songExportList.append(SongExportData(
                song: song,
                audioFileName: "songs/\(audioName)",
                coverFileName: coverName,
                lyricsFileName: lyricsName
            ))

            currentStep += 1
            progressHandler(SyncProgress(
                phase: .exporting,
                current: currentStep,
                total: totalSteps,
                currentFileName: song.title
            ))
        }

        let songExportIndex: [String: SongExportData] = Dictionary(
            songExportList.map { ("\($0.title)|\($0.artist)", $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (index, detail) in playlists.enumerated() {
            var playlistCoverName: String?
            if let coverPath = detail.playlist.coverImagePath {
                let coverSource = SandboxPathManager.playlistCoversURL
                    .appendingPathComponent(coverPath)
                if fm.fileExists(atPath: coverSource.path) {
                    playlistCoverName = "playlists/cover_\(index).jpg"
                    fileEntries.append((playlistCoverName!, coverSource))
                }
            }

            let playlistSongs: [SongExportData]
            if includeAudioFiles {
                playlistSongs = detail.songs.compactMap { song in
                    songExportIndex["\(song.title)|\(song.artist)"]
                }
            } else {
                playlistSongs = detail.songs.map { song in
                    SongExportData(song: song, audioFileName: "", coverFileName: nil, lyricsFileName: nil)
                }
            }

            let resolvedGroupName: String?
            if let groupId = detail.playlist.groupId {
                resolvedGroupName = groupNames[groupId]
            } else {
                resolvedGroupName = nil
            }

            playlistExportList.append(PlaylistExportData(
                name: detail.playlist.name,
                description: detail.playlist.description,
                groupName: resolvedGroupName,
                coverFileName: playlistCoverName,
                songs: playlistSongs,
                sortOrder: detail.playlist.sortOrder
            ))

            currentStep += 1
            progressHandler(SyncProgress(
                phase: .exporting,
                current: currentStep,
                total: totalSteps,
                currentFileName: detail.playlist.name
            ))
        }

        let deviceName = await MainActor.run { UIDevice.current.name }
        let manifest = TuneHavenManifest(
            contentType: contentType,
            deviceName: deviceName,
            songs: songExportList.isEmpty ? nil : songExportList,
            playlists: playlistExportList.isEmpty ? nil : playlistExportList
        )

        let outputURL = exportDir.appendingPathComponent("export.tunehaven")
        try writePackage(manifest: manifest, fileEntries: fileEntries, to: outputURL)

        currentStep += 1
        progressHandler(SyncProgress(
            phase: .completed,
            current: currentStep,
            total: totalSteps,
            currentFileName: nil
        ))

        return outputURL
    }

    func unpack(
        fileURL: URL,
        progressHandler: @escaping (SyncProgress) -> Void
    ) async throws -> (manifest: TuneHavenManifest, extractedDir: URL) {
        let extractDir = SandboxPathManager.syncExtractURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let magicData = handle.readData(ofLength: 8)
        guard magicData.count == 8,
              [UInt8](magicData) == Self.magic else {
            throw AppError.syncInvalidPackage("文件格式无效")
        }

        let versionData = handle.readData(ofLength: 4)
        guard versionData.count == 4 else {
            throw AppError.syncInvalidPackage("无法读取版本号")
        }
        let version = versionData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        guard version <= Self.currentVersion else {
            throw AppError.syncInvalidPackage("文件版本过高 (v\(version))，请更新 App")
        }

        let manifestLenData = handle.readData(ofLength: 4)
        guard manifestLenData.count == 4 else {
            throw AppError.syncInvalidPackage("无法读取清单长度")
        }
        let manifestLen = manifestLenData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        let manifestData = handle.readData(ofLength: Int(manifestLen))
        guard manifestData.count == Int(manifestLen) else {
            throw AppError.syncInvalidPackage("清单数据不完整")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: TuneHavenManifest
        do {
            manifest = try decoder.decode(TuneHavenManifest.self, from: manifestData)
        } catch {
            throw AppError.syncInvalidPackage("清单解析失败")
        }

        let entryCountData = handle.readData(ofLength: 4)
        guard entryCountData.count == 4 else {
            throw AppError.syncInvalidPackage("无法读取文件数量")
        }
        let entryCount = entryCountData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        progressHandler(SyncProgress(phase: .importing, current: 0, total: Int(entryCount), currentFileName: nil))

        for i in 0..<entryCount {
            let pathLenData = handle.readData(ofLength: 2)
            guard pathLenData.count == 2 else {
                throw AppError.syncInvalidPackage("文件条目 \(i) 路径长度读取失败")
            }
            let pathLen = pathLenData.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }

            let pathData = handle.readData(ofLength: Int(pathLen))
            guard pathData.count == Int(pathLen),
                  let relativePath = String(data: pathData, encoding: .utf8) else {
                throw AppError.syncInvalidPackage("文件条目 \(i) 路径读取失败")
            }

            let dataLenData = handle.readData(ofLength: 8)
            guard dataLenData.count == 8 else {
                throw AppError.syncInvalidPackage("文件条目 \(i) 数据长度读取失败")
            }
            let dataLen = dataLenData.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }

            let destURL = extractDir.appendingPathComponent(relativePath)
            let destDir = destURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: destDir.path) {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            }

            fm.createFile(atPath: destURL.path, contents: nil)
            let writeHandle = try FileHandle(forWritingTo: destURL)
            defer { try? writeHandle.close() }

            var remaining = dataLen
            while remaining > 0 {
                let chunkSize = min(UInt64(Self.streamChunkSize), remaining)
                let chunk = handle.readData(ofLength: Int(chunkSize))
                guard chunk.count == Int(chunkSize) else {
                    throw AppError.syncInvalidPackage("文件 \(relativePath) 数据不完整")
                }
                writeHandle.write(chunk)
                remaining -= UInt64(chunk.count)
            }

            progressHandler(SyncProgress(
                phase: .importing,
                current: Int(i + 1),
                total: Int(entryCount),
                currentFileName: (relativePath as NSString).lastPathComponent
            ))
        }

        return (manifest, extractDir)
    }

    func estimateExportSize(
        songs: [Song],
        playlists: [PlaylistDetail],
        includeAudioFiles: Bool
    ) -> Int64 {
        var total: Int64 = 1024 // manifest + headers overhead

        if includeAudioFiles {
            let allSongs: [Song]
            if !songs.isEmpty {
                allSongs = songs
            } else {
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
                allSongs = unique
            }
            for song in allSongs {
                total += song.fileSize
                total += 50 * 1024 // 封面+歌词估算
            }
        }

        return total
    }

    // MARK: - Cleanup

    static func cleanupExportTemp() {
        let fm = FileManager.default
        let url = SandboxPathManager.exportTempURL
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else { return }
        for item in contents {
            try? fm.removeItem(at: url.appendingPathComponent(item))
        }
    }

    static func cleanupSyncExtract() {
        let fm = FileManager.default
        let url = SandboxPathManager.syncExtractURL
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else { return }
        for item in contents {
            try? fm.removeItem(at: url.appendingPathComponent(item))
        }
    }

    // MARK: - Private

    private func writePackage(
        manifest: TuneHavenManifest,
        fileEntries: [(relativePath: String, sourceURL: URL)],
        to outputURL: URL
    ) throws {
        fm.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        handle.write(Data(Self.magic))

        var version = Self.currentVersion.littleEndian
        handle.write(Data(bytes: &version, count: 4))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let manifestData = try encoder.encode(manifest)

        var manifestLen = UInt32(manifestData.count).littleEndian
        handle.write(Data(bytes: &manifestLen, count: 4))
        handle.write(manifestData)

        var entryCount = UInt32(fileEntries.count).littleEndian
        handle.write(Data(bytes: &entryCount, count: 4))

        for entry in fileEntries {
            guard let pathData = entry.relativePath.data(using: .utf8) else { continue }
            var pathLen = UInt16(pathData.count).littleEndian
            handle.write(Data(bytes: &pathLen, count: 2))
            handle.write(pathData)

            let attrs = try fm.attributesOfItem(atPath: entry.sourceURL.path)
            let fileSize = (attrs[.size] as? UInt64) ?? 0
            var dataLen = fileSize.littleEndian
            handle.write(Data(bytes: &dataLen, count: 8))

            let readHandle = try FileHandle(forReadingFrom: entry.sourceURL)
            defer { try? readHandle.close() }
            var remaining = fileSize
            while remaining > 0 {
                let chunkSize = min(UInt64(Self.streamChunkSize), remaining)
                let chunk = readHandle.readData(ofLength: Int(chunkSize))
                guard !chunk.isEmpty else { break }
                handle.write(chunk)
                remaining -= UInt64(chunk.count)
            }
        }
    }

    private func sanitize(_ fileName: String) -> String {
        let name = (fileName as NSString).lastPathComponent
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}

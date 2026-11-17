import Foundation

/// 把旧版本放在 Caches 下的封面一次性移到 Application Support。
/// 可重入：每个文件单独移动，失败的保留在旧目录，下次启动继续。
enum CoverStorageMigration {
    struct Result: Equatable {
        var moved = 0
        var skipped = 0
        var failed = 0
    }

    @discardableResult
    static func migrate(
        legacyCovers: URL,
        legacyPlaylistCovers: URL,
        covers: URL,
        playlistCovers: URL,
        fileManager: FileManager = .default
    ) -> Result {
        var result = Result()
        // 旧 CoverImages 里与歌单封面同名的文件是拼图封面的缓存副本。
        // 取旧、新两个歌单目录的并集，上次迁移中途退出时也能识别。
        let playlistCoverNames = Set(fileNames(in: legacyPlaylistCovers, fileManager: fileManager))
            .union(fileNames(in: playlistCovers, fileManager: fileManager))

        moveContents(of: legacyPlaylistCovers, to: playlistCovers, discarding: [], result: &result, fileManager: fileManager)
        moveContents(of: legacyCovers, to: covers, discarding: playlistCoverNames, result: &result, fileManager: fileManager)
        return result
    }

    private static func moveContents(
        of source: URL,
        to destination: URL,
        discarding discardedNames: Set<String>,
        result: inout Result,
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: source.path) else { return }
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            ErrorLogger.shared.logGeneric(error, context: "封面迁移: 无法创建 \(destination.lastPathComponent)")
            result.failed += 1
            return
        }

        var failedHere = 0
        for name in fileNames(in: source, fileManager: fileManager) {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if discardedNames.contains(name) || fileManager.fileExists(atPath: to.path) {
                try? fileManager.removeItem(at: from)
                result.skipped += 1
                continue
            }
            do {
                try fileManager.moveItem(at: from, to: to)
                result.moved += 1
            } catch {
                ErrorLogger.shared.logGeneric(error, context: "封面迁移失败: \(name)")
                failedHere += 1
            }
        }
        result.failed += failedHere
        if failedHere == 0 {
            try? fileManager.removeItem(at: source)
        }
    }

    private static func fileNames(in directory: URL, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
    }
}

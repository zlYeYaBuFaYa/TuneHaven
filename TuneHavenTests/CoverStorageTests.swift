import Testing
import Foundation
import UIKit
@testable import TuneHaven

// MARK: - 测试用临时目录

private struct CoverDirs {
    let root: URL
    let legacyCovers: URL
    let legacyPlaylists: URL
    let covers: URL
    let playlists: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverStorageTests-\(UUID().uuidString)", isDirectory: true)
        legacyCovers = root.appendingPathComponent("Caches/CoverImages", isDirectory: true)
        legacyPlaylists = root.appendingPathComponent("Caches/PlaylistCovers", isDirectory: true)
        covers = root.appendingPathComponent("AppSupport/CoverImages", isDirectory: true)
        playlists = root.appendingPathComponent("AppSupport/PlaylistCovers", isDirectory: true)
    }

    func write(_ text: String, to dir: URL, name: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: dir.appendingPathComponent(name))
    }

    func read(_ dir: URL, _ name: String) -> String? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    func migrate() -> CoverStorageMigration.Result {
        CoverStorageMigration.migrate(
            legacyCovers: legacyCovers,
            legacyPlaylistCovers: legacyPlaylists,
            covers: covers,
            playlistCovers: playlists
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func jpegData(color: UIColor = .red) -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
    let image = renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
    return image.jpegData(compressionQuality: 0.9) ?? Data()
}

// MARK: - CoverStorageMigration

@Suite("CoverStorageMigration Tests")
struct CoverStorageMigrationTests {

    @Test("旧目录的歌曲封面和歌单封面移到新目录，旧目录被删除")
    func testMovesFilesAndRemovesLegacyDirs() {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        dirs.write("song", to: dirs.legacyCovers, name: "A_medium.jpg")
        dirs.write("playlist", to: dirs.legacyPlaylists, name: "P.jpg")

        let result = dirs.migrate()

        #expect(result == CoverStorageMigration.Result(moved: 2, skipped: 0, failed: 0))
        #expect(dirs.read(dirs.covers, "A_medium.jpg") == "song")
        #expect(dirs.read(dirs.playlists, "P.jpg") == "playlist")
        #expect(!dirs.exists(dirs.legacyCovers))
        #expect(!dirs.exists(dirs.legacyPlaylists))
    }

    @Test("旧 CoverImages 中与歌单封面同名的拼图副本被丢弃")
    func testDiscardsGridCoverDuplicates() {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        dirs.write("grid", to: dirs.legacyPlaylists, name: "P.jpg")
        dirs.write("stale", to: dirs.legacyCovers, name: "P.jpg")

        let result = dirs.migrate()

        #expect(result.moved == 1)
        #expect(result.skipped == 1)
        #expect(!dirs.exists(dirs.covers.appendingPathComponent("P.jpg")))
        #expect(dirs.read(dirs.playlists, "P.jpg") == "grid")
    }

    @Test("上次迁移中途退出、旧歌单目录已不在时，仍能识别拼图副本")
    func testDiscardsDuplicatesAfterPartialMigration() {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        dirs.write("grid", to: dirs.playlists, name: "P.jpg")
        dirs.write("stale", to: dirs.legacyCovers, name: "P.jpg")

        dirs.migrate()

        #expect(!dirs.exists(dirs.covers.appendingPathComponent("P.jpg")))
        #expect(!dirs.exists(dirs.legacyCovers))
    }

    @Test("目标已有同名文件时保留目标，删除旧文件")
    func testKeepsExistingDestination() {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        dirs.write("new", to: dirs.covers, name: "A_medium.jpg")
        dirs.write("old", to: dirs.legacyCovers, name: "A_medium.jpg")

        let result = dirs.migrate()

        #expect(result.skipped == 1)
        #expect(dirs.read(dirs.covers, "A_medium.jpg") == "new")
        #expect(!dirs.exists(dirs.legacyCovers))
    }

    @Test("旧目录不存在时什么都不做")
    func testNoLegacyDirs() {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }

        let result = dirs.migrate()

        #expect(result == CoverStorageMigration.Result())
        #expect(!dirs.exists(dirs.covers))
        #expect(!dirs.exists(dirs.playlists))
    }

    @Test("重复执行结果一致")
    func testIdempotent() {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        dirs.write("song", to: dirs.legacyCovers, name: "A_medium.jpg")

        dirs.migrate()
        let second = dirs.migrate()

        #expect(second == CoverStorageMigration.Result())
        #expect(dirs.read(dirs.covers, "A_medium.jpg") == "song")
    }
}

// MARK: - ImageCacheManager

@Suite("ImageCacheManager Storage Tests")
struct ImageCacheManagerStorageTests {

    private func makeCache(_ dirs: CoverDirs) -> ImageCacheManager {
        try? FileManager.default.createDirectory(at: dirs.covers, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dirs.playlists, withIntermediateDirectories: true)
        return ImageCacheManager(coverDirectory: dirs.covers, playlistCoverDirectory: dirs.playlists)
    }

    @Test("歌单封面从 PlaylistCovers 读取")
    func testReadsPlaylistCover() async {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        let cache = makeCache(dirs)
        try? jpegData().write(to: dirs.playlists.appendingPathComponent("P.jpg"))

        let image = await cache.imageAsync(forKey: "P.jpg")

        #expect(image != nil)
    }

    @Test("歌曲封面从 CoverImages 读取")
    func testReadsSongCover() async {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        let cache = makeCache(dirs)
        try? jpegData().write(to: dirs.covers.appendingPathComponent("A_medium.jpg"))

        let image = await cache.imageAsync(forKey: "A_medium.jpg")

        #expect(image != nil)
    }

    @Test("两个目录都没有时返回 nil")
    func testMissingReturnsNil() async {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        let cache = makeCache(dirs)

        #expect(await cache.imageAsync(forKey: "missing.jpg") == nil)
    }

    @Test("store 只更新内存，不在磁盘写文件")
    @MainActor
    func testStoreDoesNotWriteDisk() {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        let cache = makeCache(dirs)
        let image = UIImage(data: jpegData()) ?? UIImage()

        cache.store(image: image, forKey: "A_medium.jpg")

        #expect(cache.memoryImage(forKey: "A_medium.jpg") != nil)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dirs.covers.path))?.isEmpty == true)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dirs.playlists.path))?.isEmpty == true)
    }

    @Test("设置自定义歌单封面后，内存缓存立即换成新图且文件写入 PlaylistCovers")
    @MainActor
    func testCustomPlaylistCoverRefreshesMemoryCache() async throws {
        SandboxPathManager.createAllDirectories()
        let cache = ImageCacheManager(
            coverDirectory: SandboxPathManager.coverImagesURL,
            playlistCoverDirectory: SandboxPathManager.playlistCoversURL
        )
        let playlistId = UUID()
        let fileURL = SandboxPathManager.playlistCoverURL(playlistId: playlistId)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let processor = CoverImageProcessor(imageCache: cache)

        let key = try await processor.processPlaylistCover(imageData: jpegData(color: .blue), playlistId: playlistId)

        #expect(key == "\(playlistId.uuidString).jpg")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(cache.memoryImage(forKey: key) != nil)
    }

    @Test("占用统计包含两个目录")
    func testStorageSizeCountsBothDirs() async {
        let dirs = CoverDirs()
        defer { dirs.cleanup() }
        let cache = makeCache(dirs)
        try? Data(count: 100).write(to: dirs.covers.appendingPathComponent("A_medium.jpg"))
        try? Data(count: 50).write(to: dirs.playlists.appendingPathComponent("P.jpg"))

        #expect(await cache.cacheSizeAsync() == 150)
    }
}

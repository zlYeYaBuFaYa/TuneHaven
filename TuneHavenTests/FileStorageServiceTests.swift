import Testing
import Foundation
@testable import TuneHaven

// MARK: - FileStorageService Tests

@Suite("FileStorageService Tests")
struct FileStorageServiceTests {

    private let service = FileStorageService.shared

    // MARK: - 支持的文件格式

    @Test("支持的格式集合包含所有核心格式")
    func testSupportedExtensionsContainsCoreFormats() {
        let required = ["mp3", "m4a", "aac", "alac", "wav", "flac", "aiff", "aif", "caf"]
        for ext in required {
            #expect(FileStorageService.supportedExtensions.contains(ext), "格式 \(ext) 应被支持")
        }
    }

    @Test("不支持的格式不在集合中")
    func testUnsupportedExtensions() {
        let unsupported = ["mp4", "mov", "avi", "mkv", "txt", "pdf", "jpg", "ogg", "wma", "ape"]
        for ext in unsupported {
            #expect(!FileStorageService.supportedExtensions.contains(ext), "格式 \(ext) 不应被支持")
        }
    }

    @Test("无损格式均被支持")
    func testLosslessFormatsSupported() {
        let lossless = ["flac", "alac", "wav", "aiff", "aif", "caf"]
        for ext in lossless {
            #expect(FileStorageService.supportedExtensions.contains(ext), "无损格式 \(ext) 应被支持")
        }
    }

    @Test("支持格式大小写敏感（小写）")
    func testSupportedExtensionsLowercase() {
        // 支持格式集合存储的是小写格式
        #expect(FileStorageService.supportedExtensions.contains("mp3"))
        #expect(!FileStorageService.supportedExtensions.contains("MP3"))
        #expect(!FileStorageService.supportedExtensions.contains("Mp3"))
    }

    // MARK: - 文件大小限制

    @Test("最大文件大小为 500MB")
    func testMaxFileSizeIs500MB() {
        let expected: Int64 = 500 * 1024 * 1024
        #expect(FileStorageService.maxFileSizeBytes == expected)
    }

    @Test("500MB 文件在限制范围内")
    func testFileSizeAtLimit() {
        let size: Int64 = 500 * 1024 * 1024
        #expect(size <= FileStorageService.maxFileSizeBytes)
    }

    @Test("超过 500MB 的文件超出限制")
    func testFileSizeOverLimit() {
        let oversizeBytes: Int64 = 501 * 1024 * 1024
        #expect(oversizeBytes > FileStorageService.maxFileSizeBytes)
    }

    @Test("1 字节的文件在限制范围内")
    func testTinyFileSizeInLimit() {
        let size: Int64 = 1
        #expect(size <= FileStorageService.maxFileSizeBytes)
    }

    // MARK: - SHA256 哈希计算

    @Test("SHA256 对相同内容输出相同哈希值")
    func testSHA256SameContent() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_sha256_\(UUID().uuidString).txt")
        let content = "Hello, World! 音乐文件测试内容"
        try content.data(using: .utf8)!.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let hash1 = try service.sha256(of: fileURL)
        let hash2 = try service.sha256(of: fileURL)

        #expect(hash1 == hash2)
    }

    @Test("SHA256 对不同内容输出不同哈希值")
    func testSHA256DifferentContent() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url1 = tempDir.appendingPathComponent("test_sha256_a_\(UUID().uuidString).txt")
        let url2 = tempDir.appendingPathComponent("test_sha256_b_\(UUID().uuidString).txt")
        try "Content A".data(using: .utf8)!.write(to: url1)
        try "Content B".data(using: .utf8)!.write(to: url2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let hash1 = try service.sha256(of: url1)
        let hash2 = try service.sha256(of: url2)

        #expect(hash1 != hash2)
    }

    @Test("SHA256 返回 64 位十六进制字符串（256位 = 32字节 = 64个十六进制字符）")
    func testSHA256OutputLength() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_sha256_len_\(UUID().uuidString).txt")
        try "Test content".data(using: .utf8)!.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let hash = try service.sha256(of: fileURL)
        #expect(hash.count == 64)
    }

    @Test("SHA256 输出只包含十六进制字符")
    func testSHA256OutputIsHex() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_sha256_hex_\(UUID().uuidString).txt")
        try "Test content for hex check".data(using: .utf8)!.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let hash = try service.sha256(of: fileURL)
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(hash.unicodeScalars.allSatisfy { hexCharSet.contains($0) })
    }

    @Test("SHA256 文件不存在时抛出错误")
    func testSHA256NonexistentFile() {
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/to/file.mp3")
        #expect(throws: (any Error).self) {
            try service.sha256(of: nonexistentURL)
        }
    }

    // MARK: - 文件大小获取

    @Test("fileSize 返回正确的文件大小")
    func testFileSizeReturnsCorrectSize() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_filesize_\(UUID().uuidString).txt")
        let content = "12345678901234567890" // 20 字节
        let data = content.data(using: .utf8)!
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let size = service.fileSize(at: fileURL)
        #expect(size == Int64(data.count))
    }

    @Test("fileSize 不存在的文件返回 0")
    func testFileSizeNonexistentFile() {
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/file.mp3")
        let size = service.fileSize(at: nonexistentURL)
        #expect(size == 0)
    }

    // MARK: - 文件是否存在

    @Test("fileExists 存在的文件返回 true")
    func testFileExistsTrue() throws {
        // 需要先在沙盒 Music 目录放一个文件
        SandboxPathManager.createAllDirectories()
        let testRelPath = "test_exists_\(UUID().uuidString).txt"
        let url = SandboxPathManager.musicFileURL(relativePath: testRelPath)
        try "test".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(service.fileExists(relativePath: testRelPath))
    }

    @Test("fileExists 不存在的文件返回 false")
    func testFileExistsFalse() {
        #expect(!service.fileExists(relativePath: "nonexistent_\(UUID().uuidString).mp3"))
    }
}

// MARK: - SandboxPathManager Tests

@Suite("SandboxPathManager Tests")
struct SandboxPathManagerTests {

    @Test("documentsURL 路径包含 Documents")
    func testDocumentsURL() {
        let url = SandboxPathManager.documentsURL
        #expect(url.path.contains("Documents"))
    }

    @Test("musicURL 是 Documents/Music 子目录")
    func testMusicURL() {
        let url = SandboxPathManager.musicURL
        #expect(url.path.hasSuffix("Music"))
        #expect(url.path.contains("Documents"))
    }

    @Test("lyricsURL 是 Documents/Lyrics 子目录")
    func testLyricsURL() {
        let url = SandboxPathManager.lyricsURL
        #expect(url.path.hasSuffix("Lyrics"))
        #expect(url.path.contains("Documents"))
    }

    @Test("cachesURL 路径包含 Caches")
    func testCachesURL() {
        let url = SandboxPathManager.cachesURL
        #expect(url.path.contains("Caches"))
    }

    @Test("coverImagesURL 是 Caches/CoverImages 子目录")
    func testCoverImagesURL() {
        let url = SandboxPathManager.coverImagesURL
        #expect(url.path.hasSuffix("CoverImages"))
    }

    @Test("playlistCoversURL 是 Caches/PlaylistCovers 子目录")
    func testPlaylistCoversURL() {
        let url = SandboxPathManager.playlistCoversURL
        #expect(url.path.hasSuffix("PlaylistCovers"))
    }

    @Test("pendingDeleteURL 在 tmp 目录下")
    func testPendingDeleteURL() {
        let url = SandboxPathManager.pendingDeleteURL
        #expect(url.path.hasSuffix("pending_delete"))
    }

    @Test("musicFileURL 返回 Music 目录下的正确路径")
    func testMusicFileURL() {
        let relPath = "abc12345_夜曲.mp3"
        let url = SandboxPathManager.musicFileURL(relativePath: relPath)
        #expect(url.path.hasSuffix(relPath))
        #expect(url.path.contains("Music"))
    }

    @Test("lyricsFileURL 返回 Lyrics 目录下的正确路径")
    func testLyricsFileURL() {
        let relPath = "song123.lrc"
        let url = SandboxPathManager.lyricsFileURL(relativePath: relPath)
        #expect(url.path.hasSuffix(relPath))
        #expect(url.path.contains("Lyrics"))
    }

    @Test("coverImageURL 包含 songId 和 size 后缀")
    func testCoverImageURL() {
        let songId = UUID()
        let url = SandboxPathManager.coverImageURL(songId: songId, size: .medium)
        #expect(url.path.contains(songId.uuidString))
        #expect(url.path.contains("medium"))
        #expect(url.path.hasSuffix(".jpg"))
    }

    @Test("playlistCoverURL 包含 playlistId")
    func testPlaylistCoverURL() {
        let playlistId = UUID()
        let url = SandboxPathManager.playlistCoverURL(playlistId: playlistId)
        #expect(url.path.contains(playlistId.uuidString))
        #expect(url.path.hasSuffix(".jpg"))
    }

    @Test("createAllDirectories 创建所有必要目录")
    func testCreateAllDirectories() {
        SandboxPathManager.createAllDirectories()
        let fm = FileManager.default
        let dirs = [
            SandboxPathManager.musicURL,
            SandboxPathManager.lyricsURL,
            SandboxPathManager.coverImagesURL,
            SandboxPathManager.playlistCoversURL,
            SandboxPathManager.pendingDeleteURL,
            SandboxPathManager.wifiUploadURL,
            SandboxPathManager.importTempURL
        ]
        for dir in dirs {
            #expect(fm.fileExists(atPath: dir.path), "目录 \(dir.lastPathComponent) 应被创建")
        }
    }
}

// MARK: - ThumbnailSize Tests

@Suite("ThumbnailSize Tests")
struct ThumbnailSizeTests {

    @Test("small 尺寸为 100pt")
    func testSmallSize() {
        #expect(ThumbnailSize.small.dimension == 100)
    }

    @Test("medium 尺寸为 200pt")
    func testMediumSize() {
        #expect(ThumbnailSize.medium.dimension == 200)
    }

    @Test("large 尺寸为 400pt")
    func testLargeSize() {
        #expect(ThumbnailSize.large.dimension == 400)
    }

    @Test("original 尺寸上限为 1024pt")
    func testOriginalSize() {
        #expect(ThumbnailSize.original.dimension == 1024)
    }

    @Test("suffix 与 rawValue 一致")
    func testSuffix() {
        for size in [ThumbnailSize.small, .medium, .large, .original] {
            #expect(size.suffix == size.rawValue)
        }
    }
}

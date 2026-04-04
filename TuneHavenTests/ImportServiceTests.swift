import Testing
import Foundation
@testable import TuneHaven

@Suite("ImportService Tests")
@MainActor
struct ImportServiceTests {
    let mockSongRepo = MockSongRepository()
    let mockFileStorage = MockFileStorageProviding()
    let mockCoverProcessor = MockCoverImageProcessing()
    let mockMetadataParser = MockAudioMetadataParsing()

    func makeService() -> ImportService {
        ImportService(
            songRepo: mockSongRepo,
            fileService: mockFileStorage,
            coverProcessor: mockCoverProcessor,
            metadataParser: mockMetadataParser
        )
    }

    // MARK: - Successful import

    @Test("单文件导入成功")
    func testSingleFileImportSuccess() async {
        let svc = makeService()
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test.mp3")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(repeating: 0, count: 1024))
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = await svc.importFromFiles(urls: [tempFile]) { _ in }
        #expect(result.successCount == 1)
        #expect(result.failedCount == 0)
        #expect(result.skippedDuplicateCount == 0)
        #expect(mockSongRepo.songs.count == 1)
    }

    // MARK: - Unsupported format

    @Test("不支持的格式被跳过")
    func testUnsupportedFormatSkipped() async {
        let svc = makeService()
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test.ogg")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(repeating: 0, count: 64))
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = await svc.importFromFiles(urls: [tempFile]) { _ in }
        #expect(result.skippedFormatCount == 1)
        #expect(result.successCount == 0)
    }

    // MARK: - Duplicate detection

    @Test("重复文件被跳过")
    func testDuplicateDetection() async {
        let svc = makeService()
        let existingSong = makeSong(fileHash: "mockhash12345678")
        mockSongRepo.songs = [existingSong]

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("dup.mp3")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(repeating: 0, count: 1024))
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = await svc.importFromFiles(urls: [tempFile]) { _ in }
        #expect(result.skippedDuplicateCount == 1)
        #expect(result.successCount == 0)
    }

    // MARK: - Oversize file

    @Test("超大文件被跳过")
    func testOversizeFileSkipped() async {
        let svc = makeService()
        mockFileStorage.maxFileSizeBytes = 100

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("big.mp3")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(repeating: 0, count: 1024))
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = await svc.importFromFiles(urls: [tempFile]) { _ in }
        #expect(result.skippedOversizeCount == 1)
    }

    // MARK: - Progress callback

    @Test("导入过程中触发进度回调")
    func testProgressCallback() async {
        let svc = makeService()
        var progressUpdates: [ImportProgress] = []

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile1 = tempDir.appendingPathComponent("s1.mp3")
        let tempFile2 = tempDir.appendingPathComponent("s2.mp3")
        FileManager.default.createFile(atPath: tempFile1.path, contents: Data(repeating: 0, count: 64))
        FileManager.default.createFile(atPath: tempFile2.path, contents: Data(repeating: 0, count: 64))
        defer {
            try? FileManager.default.removeItem(at: tempFile1)
            try? FileManager.default.removeItem(at: tempFile2)
        }

        _ = await svc.importFromFiles(urls: [tempFile1, tempFile2]) { p in
            progressUpdates.append(p)
        }
        #expect(progressUpdates.count == 2)
        #expect(progressUpdates[0].totalCount == 2)
    }

    // MARK: - Cancel

    @Test("第一个文件处理后取消，后续文件不再处理")
    func testCancelImport() async {
        let svc = makeService()
        var urls: [URL] = []
        let tempDir = FileManager.default.temporaryDirectory
        for i in 0..<5 {
            let f = tempDir.appendingPathComponent("c\(i).mp3")
            FileManager.default.createFile(atPath: f.path, contents: Data(repeating: 0, count: 64))
            urls.append(f)
        }
        defer {
            for f in urls { try? FileManager.default.removeItem(at: f) }
        }

        let result = await svc.importFromFiles(urls: urls) { progress in
            if progress.completedCount == 1 {
                svc.cancelImport()
            }
        }
        #expect(result.successCount < 5)
    }

    // MARK: - onNewSongsImported callback

    @Test("导入成功后触发 onNewSongsImported 回调")
    func testOnNewSongsImportedCallback() async {
        let svc = makeService()
        var callbackCalled = false
        svc.onNewSongsImported = { callbackCalled = true }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("cb.mp3")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(repeating: 0, count: 64))
        defer { try? FileManager.default.removeItem(at: tempFile) }

        _ = await svc.importFromFiles(urls: [tempFile]) { _ in }
        #expect(callbackCalled)
    }

    // MARK: - isImporting state

    @Test("导入期间 isImporting 为 true，完成后为 false")
    func testIsImportingState() async {
        let svc = makeService()
        #expect(svc.isImporting == false)

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("state.mp3")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(repeating: 0, count: 64))
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var wasImporting = false
        _ = await svc.importFromFiles(urls: [tempFile]) { _ in
            if svc.isImporting { wasImporting = true }
        }
        #expect(wasImporting)
        #expect(svc.isImporting == false)
    }
}

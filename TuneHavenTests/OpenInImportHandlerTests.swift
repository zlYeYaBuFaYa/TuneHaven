import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("从「文件」打开音频：安全范围与提示")
struct OpenInImportHandlerTests {
    @Test("先获取安全范围再判断存在性，导入后释放")
    func testAccessBeginsBeforeExistenceCheck() async {
        let fileStorage = MockFileStorageProviding()
        // 未获取安全范围前，iCloud 等原位文件看起来不存在
        fileStorage.fileExistsResult = false
        let snackbar = SnackbarState()
        var ended: [URL] = []
        let handler = makeHandler(
            fileStorage: fileStorage,
            snackbar: snackbar,
            beginAccess: { _ in fileStorage.fileExistsResult = true; return true },
            endAccess: { ended.append($0) }
        )
        let url = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/song.mp3")

        handler.enqueue(url: url)
        await waitUntil { !ended.isEmpty }

        #expect(snackbar.message.hasPrefix("已导入"))
        #expect(ended == [url])
        #expect(fileStorage.removedItems.isEmpty)
    }

    @Test("拿不到安全范围且文件不可读时提示用户，不静默跳过")
    func testInaccessibleFileShowsNotice() async {
        let fileStorage = MockFileStorageProviding()
        fileStorage.fileExistsResult = false
        let snackbar = SnackbarState()
        var ended = 0
        let handler = makeHandler(
            fileStorage: fileStorage,
            snackbar: snackbar,
            beginAccess: { _ in false },
            endAccess: { _ in ended += 1 }
        )

        handler.enqueue(url: URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/song.flac"))
        await waitUntil { snackbar.isShowing }

        #expect(snackbar.message == OpenInImportHandler.inaccessibleNotice)
        #expect(ended == 0)
    }

    @Test("拿到安全范围但文件已不存在时提示找不到")
    func testMissingScopedFileShowsMissingNotice() async {
        let fileStorage = MockFileStorageProviding()
        fileStorage.fileExistsResult = false
        let snackbar = SnackbarState()
        var ended = 0
        let handler = makeHandler(
            fileStorage: fileStorage,
            snackbar: snackbar,
            beginAccess: { _ in true },
            endAccess: { _ in ended += 1 }
        )

        handler.enqueue(url: URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/song.m4a"))
        await waitUntil { snackbar.isShowing }

        #expect(snackbar.message == OpenInImportHandler.missingNotice)
        #expect(ended == 1)
    }

    @Test("Inbox 副本不在安全范围内，丢失时提示找不到而非下载")
    func testMissingInboxCopyShowsMissingNotice() async {
        let fileStorage = MockFileStorageProviding()
        fileStorage.fileExistsResult = false
        let snackbar = SnackbarState()
        let handler = makeHandler(
            fileStorage: fileStorage,
            snackbar: snackbar,
            beginAccess: { _ in false },
            endAccess: { _ in }
        )
        let inboxURL = fileStorage.documentsURL
            .appendingPathComponent("Inbox")
            .appendingPathComponent("song.mp3")

        handler.enqueue(url: inboxURL)
        await waitUntil { snackbar.isShowing }

        #expect(snackbar.message == OpenInImportHandler.missingNotice)
    }

    private func makeHandler(
        fileStorage: MockFileStorageProviding,
        snackbar: SnackbarState,
        beginAccess: @escaping (URL) -> Bool,
        endAccess: @escaping (URL) -> Void
    ) -> OpenInImportHandler {
        let importService = ImportService(
            songRepo: MockSongRepository(),
            fileService: fileStorage,
            coverProcessor: MockCoverImageProcessing(),
            metadataParser: MockAudioMetadataParsing()
        )
        return OpenInImportHandler(
            importService: importService,
            libraryService: MusicLibraryService(songRepo: MockSongRepository(), imageCache: MockImageCacheManaging()),
            fileStorage: fileStorage,
            snackbar: snackbar,
            beginAccess: beginAccess,
            endAccess: endAccess
        )
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

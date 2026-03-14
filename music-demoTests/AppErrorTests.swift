import Testing
@testable import music_demo

// MARK: - AppError Tests

@Suite("AppError Tests")
struct AppErrorTests {

    // MARK: - 错误码测试

    @Test("导入相关错误码正确")
    func testImportErrorCodes() {
        #expect(AppError.importUnsupportedFormat("mp4").errorCode == "IMP001")
        #expect(AppError.importFileTooLarge(600 * 1024 * 1024).errorCode == "IMP002")
        #expect(AppError.importFileCorrupted("test.mp3").errorCode == "IMP003")
        #expect(AppError.importReadFailed("test.mp3").errorCode == "IMP004")
        #expect(AppError.importDuplicate("test.mp3").errorCode == "IMP005")
    }

    @Test("播放相关错误码正确")
    func testPlaybackErrorCodes() {
        let id = UUID()
        #expect(AppError.playbackFileNotFound(id).errorCode == "PLY001")
        #expect(AppError.playbackFileCorrupted(id).errorCode == "PLY002")
        #expect(AppError.playbackUnsupportedFormat("flac").errorCode == "PLY003")
    }

    @Test("WiFi 传输错误码正确")
    func testWiFiErrorCodes() {
        #expect(AppError.wifiServerStartFailed.errorCode == "WIF001")
        #expect(AppError.wifiNotConnected.errorCode == "WIF002")
        #expect(AppError.wifiPasswordWrong.errorCode == "WIF003")
        #expect(AppError.wifiBruteForceDetected.errorCode == "WIF004")
    }

    @Test("权限相关错误码正确")
    func testPermissionErrorCodes() {
        #expect(AppError.permissionFileAccess.errorCode == "PRM001")
        #expect(AppError.permissionNotification.errorCode == "PRM002")
        #expect(AppError.permissionMediaLibrary.errorCode == "PRM003")
    }

    @Test("存储和数据库错误码正确")
    func testStorageErrorCodes() {
        #expect(AppError.storageFull.errorCode == "STO001")
        #expect(AppError.databaseError(NSError(domain: "test", code: 0)).errorCode == "DB001")
    }

    @Test("歌单相关错误码正确")
    func testPlaylistErrorCodes() {
        #expect(AppError.playlistNameDuplicate.errorCode == "PLT001")
        #expect(AppError.playlistNameEmpty.errorCode == "PLT002")
    }

    @Test("播放队列错误码正确")
    func testQueueErrorCode() {
        #expect(AppError.playQueueFull.errorCode == "QUE001")
    }

    // MARK: - 错误描述测试

    @Test("导入格式不支持错误描述包含格式名称")
    func testImportUnsupportedFormatDescription() {
        let error = AppError.importUnsupportedFormat("mp4")
        #expect(error.errorDescription?.contains("mp4") == true)
    }

    @Test("文件过大错误描述包含 500MB 提示")
    func testImportFileTooLargeDescription() {
        let error = AppError.importFileTooLarge(600 * 1024 * 1024)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("500") || desc.contains("过大"))
    }

    @Test("播放文件不存在错误描述包含关键词")
    func testPlaybackFileNotFoundDescription() {
        let error = AppError.playbackFileNotFound(UUID())
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("不存在") || desc.contains("删除") || desc.contains("移动"))
    }

    @Test("WiFi 密码错误描述包含提示")
    func testWifiPasswordWrongDescription() {
        let error = AppError.wifiPasswordWrong
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("密码"))
    }

    @Test("WiFi 暴力破解错误描述提示稍后再试")
    func testWifiBruteForceDescription() {
        let error = AppError.wifiBruteForceDetected
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("稍后") || desc.contains("多次"))
    }

    @Test("通知权限错误描述包含关键词")
    func testPermissionNotificationDescription() {
        let error = AppError.permissionNotification
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("通知") || desc.contains("权限"))
    }

    @Test("文件访问权限错误描述包含设置入口提示")
    func testPermissionFileAccessDescription() {
        let error = AppError.permissionFileAccess
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("设置") || desc.contains("授权") || desc.contains("访问"))
    }

    @Test("歌单名称重复错误有描述")
    func testPlaylistNameDuplicateDescription() {
        let error = AppError.playlistNameDuplicate
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("歌单名称为空错误有描述")
    func testPlaylistNameEmptyDescription() {
        let error = AppError.playlistNameEmpty
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("数据库错误描述包含原始错误信息")
    func testDatabaseErrorDescription() {
        let underlyingError = NSError(domain: "CoreData", code: 512, userInfo: [NSLocalizedDescriptionKey: "数据写入失败"])
        let error = AppError.databaseError(underlyingError)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("数据"))
    }

    // MARK: - LocalizedError 协议

    @Test("AppError 实现了 LocalizedError 协议，errorDescription 不为空")
    func testAllErrorsHaveDescriptions() {
        let id = UUID()
        let errors: [AppError] = [
            .importUnsupportedFormat("test"),
            .importFileTooLarge(1024),
            .importFileCorrupted("test"),
            .importReadFailed("test"),
            .importDuplicate("test"),
            .playbackFileNotFound(id),
            .playbackFileCorrupted(id),
            .playbackUnsupportedFormat("flac"),
            .wifiServerStartFailed,
            .wifiNotConnected,
            .wifiPasswordWrong,
            .wifiBruteForceDetected,
            .permissionFileAccess,
            .permissionNotification,
            .permissionMediaLibrary,
            .storageFull,
            .databaseError(NSError(domain: "test", code: 0)),
            .playlistNameDuplicate,
            .playlistNameEmpty,
            .playQueueFull
        ]

        for error in errors {
            #expect(error.errorDescription != nil, "错误 \(error) 的 errorDescription 不应为 nil")
            #expect(!(error.errorDescription?.isEmpty ?? true), "错误 \(error) 的 errorDescription 不应为空字符串")
        }
    }

    @Test("所有错误码都唯一")
    func testAllErrorCodesAreUnique() {
        let id = UUID()
        let errorCodes: [String] = [
            AppError.importUnsupportedFormat("test").errorCode,
            AppError.importFileTooLarge(1024).errorCode,
            AppError.importFileCorrupted("test").errorCode,
            AppError.importReadFailed("test").errorCode,
            AppError.importDuplicate("test").errorCode,
            AppError.playbackFileNotFound(id).errorCode,
            AppError.playbackFileCorrupted(id).errorCode,
            AppError.playbackUnsupportedFormat("flac").errorCode,
            AppError.wifiServerStartFailed.errorCode,
            AppError.wifiNotConnected.errorCode,
            AppError.wifiPasswordWrong.errorCode,
            AppError.wifiBruteForceDetected.errorCode,
            AppError.permissionFileAccess.errorCode,
            AppError.permissionNotification.errorCode,
            AppError.permissionMediaLibrary.errorCode,
            AppError.storageFull.errorCode,
            AppError.databaseError(NSError(domain: "test", code: 0)).errorCode,
            AppError.playlistNameDuplicate.errorCode,
            AppError.playlistNameEmpty.errorCode,
            AppError.playQueueFull.errorCode
        ]

        let uniqueCodes = Set(errorCodes)
        #expect(errorCodes.count == uniqueCodes.count, "发现重复的错误码")
    }
}

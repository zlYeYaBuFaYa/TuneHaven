import Foundation

enum AppError: LocalizedError {
    case importUnsupportedFormat(String)
    case importFileTooLarge(Int64)
    case importFileCorrupted(String)
    case importReadFailed(String)
    case importDuplicate(String)
    case playbackFileNotFound(UUID)
    case playbackFileCorrupted(UUID)
    case playbackUnsupportedFormat(String)
    case playbackSessionFailed
    case playbackLoadFailed(String)
    case wifiServerStartFailed
    case wifiNotConnected
    case wifiPasswordWrong
    case wifiBruteForceDetected
    case permissionFileAccess
    case permissionNotification
    case permissionMediaLibrary
    case storageFull
    case databaseError(Error)
    case playlistNameDuplicate
    case playlistNameEmpty
    case playQueueFull
    case webdavConnectionFailed(String)
    case webdavAuthFailed
    case webdavServerNotSupported
    case webdavDownloadFailed(String)
    case webdavCertificateError
    case lyricsSearchFailed(String)
    case lyricsSaveFailed(String)
    case lyricsImportFailed(String)
    case lyricsDeleteFailed(String)
    case fileSystemError(String)
    case imageProcessingFailed(String)
    case purchaseFailed(String)
    case featureRequiresPremium(String)
    case backupInvalidPackage(String)
    case backupUnsupportedVersion(Int)
    case backupCancelled
    case backupCommitRolledBack(String)

    var errorDescription: String? {
        switch self {
        case .importUnsupportedFormat(let f): return "格式不支持：\(f)"
        case .importFileTooLarge: return "文件过大（超过500MB），已跳过"
        case .importFileCorrupted(let f): return "文件已损坏：\(f)"
        case .importReadFailed(let f): return "文件读取失败：\(f)"
        case .importDuplicate(let f): return "文件已存在（跳过重复文件）：\(f)"
        case .playbackFileNotFound: return "文件不存在，该文件已被删除或移动"
        case .playbackFileCorrupted: return "无法播放歌曲，文件已损坏"
        case .playbackUnsupportedFormat(let f): return "格式不支持：\(f)"
        case .playbackSessionFailed: return "音频会话激活失败，请重试"
        case .playbackLoadFailed(let msg): return "音频加载失败：\(msg)"
        case .wifiServerStartFailed: return "WiFi传输服务启动失败"
        case .wifiNotConnected: return "请确保手机和电脑在同一WiFi网络"
        case .wifiPasswordWrong: return "密码错误，请检查密码是否正确"
        case .wifiBruteForceDetected: return "检测到多次错误密码尝试，请稍后再试"
        case .permissionFileAccess: return "文件访问授权失败，请在系统设置中允许本应用访问文件"
        case .permissionNotification: return "本地通知权限未开启，定时播放提醒将无法使用"
        case .permissionMediaLibrary: return "媒体库权限未开启，请在系统设置中允许访问"
        case .storageFull: return "存储空间不足，请清理设备空间后重试"
        case .databaseError(let e): return "数据库错误：\(e.localizedDescription)"
        case .playlistNameDuplicate: return "歌单名称已存在"
        case .playlistNameEmpty: return "歌单名称不能为空"
        case .playQueueFull: return "播放队列已满（999首）"
        case .webdavConnectionFailed(let msg): return "WebDAV 连接失败：\(msg)"
        case .webdavAuthFailed: return "WebDAV 用户名或密码错误"
        case .webdavServerNotSupported: return "服务器不支持 WebDAV 协议"
        case .webdavDownloadFailed(let msg): return "WebDAV 下载失败：\(msg)"
        case .webdavCertificateError: return "SSL 证书验证失败"
        case .lyricsSearchFailed: return "歌词搜索失败，请检查网络连接"
        case .lyricsSaveFailed: return "歌词保存失败"
        case .lyricsImportFailed: return "歌词导入失败，请确认文件格式正确"
        case .lyricsDeleteFailed: return "歌词删除失败"
        case .fileSystemError(let msg): return "文件系统错误：\(msg)"
        case .imageProcessingFailed(let msg): return "图片处理失败：\(msg)"
        case .purchaseFailed(let msg): return "购买失败：\(msg)"
        case .featureRequiresPremium(let f): return "此功能需要 Premium 订阅：\(f)"
        case .backupInvalidPackage(let msg): return "备份包无效：\(msg)"
        case .backupUnsupportedVersion(let v): return "不支持的备份版本：\(v)"
        case .backupCancelled: return "备份或恢复已取消"
        case .backupCommitRolledBack(let msg): return "恢复已回滚：\(msg)"
        }
    }

    var errorCode: String {
        switch self {
        case .importUnsupportedFormat: return "IMP001"
        case .importFileTooLarge: return "IMP002"
        case .importFileCorrupted: return "IMP003"
        case .importReadFailed: return "IMP004"
        case .importDuplicate: return "IMP005"
        case .playbackFileNotFound: return "PLY001"
        case .playbackFileCorrupted: return "PLY002"
        case .playbackUnsupportedFormat: return "PLY003"
        case .playbackSessionFailed: return "PLY004"
        case .playbackLoadFailed: return "PLY005"
        case .wifiServerStartFailed: return "WIF001"
        case .wifiNotConnected: return "WIF002"
        case .wifiPasswordWrong: return "WIF003"
        case .wifiBruteForceDetected: return "WIF004"
        case .permissionFileAccess: return "PRM001"
        case .permissionNotification: return "PRM002"
        case .permissionMediaLibrary: return "PRM003"
        case .storageFull: return "STO001"
        case .databaseError: return "DB001"
        case .playlistNameDuplicate: return "PLT001"
        case .playlistNameEmpty: return "PLT002"
        case .playQueueFull: return "QUE001"
        case .webdavConnectionFailed: return "DAV001"
        case .webdavAuthFailed: return "DAV002"
        case .webdavServerNotSupported: return "DAV003"
        case .webdavDownloadFailed: return "DAV004"
        case .webdavCertificateError: return "DAV005"
        case .lyricsSearchFailed: return "LYR001"
        case .lyricsSaveFailed: return "LYR002"
        case .lyricsImportFailed: return "LYR003"
        case .lyricsDeleteFailed: return "LYR004"
        case .fileSystemError: return "FS001"
        case .imageProcessingFailed: return "IMG001"
        case .purchaseFailed: return "SUB001"
        case .featureRequiresPremium: return "SUB002"
        case .backupInvalidPackage: return "BKP001"
        case .backupUnsupportedVersion: return "BKP002"
        case .backupCancelled: return "BKP003"
        case .backupCommitRolledBack: return "BKP004"
        }
    }
}

// MARK: - Equatable（完整值比较，包含所有关联值）
extension AppError: Equatable {
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.importUnsupportedFormat(let a), .importUnsupportedFormat(let b)): return a == b
        case (.importFileTooLarge(let a), .importFileTooLarge(let b)): return a == b
        case (.importFileCorrupted(let a), .importFileCorrupted(let b)): return a == b
        case (.importReadFailed(let a), .importReadFailed(let b)): return a == b
        case (.importDuplicate(let a), .importDuplicate(let b)): return a == b
        case (.playbackFileNotFound(let a), .playbackFileNotFound(let b)): return a == b
        case (.playbackFileCorrupted(let a), .playbackFileCorrupted(let b)): return a == b
        case (.playbackUnsupportedFormat(let a), .playbackUnsupportedFormat(let b)): return a == b
        case (.playbackSessionFailed, .playbackSessionFailed): return true
        case (.playbackLoadFailed(let a), .playbackLoadFailed(let b)): return a == b
        case (.wifiServerStartFailed, .wifiServerStartFailed): return true
        case (.wifiNotConnected, .wifiNotConnected): return true
        case (.wifiPasswordWrong, .wifiPasswordWrong): return true
        case (.wifiBruteForceDetected, .wifiBruteForceDetected): return true
        case (.permissionFileAccess, .permissionFileAccess): return true
        case (.permissionNotification, .permissionNotification): return true
        case (.permissionMediaLibrary, .permissionMediaLibrary): return true
        case (.storageFull, .storageFull): return true
        case (.databaseError(let a), .databaseError(let b)):
            return String(describing: a) == String(describing: b)
        case (.playlistNameDuplicate, .playlistNameDuplicate): return true
        case (.playlistNameEmpty, .playlistNameEmpty): return true
        case (.playQueueFull, .playQueueFull): return true
        case (.webdavConnectionFailed(let a), .webdavConnectionFailed(let b)): return a == b
        case (.webdavAuthFailed, .webdavAuthFailed): return true
        case (.webdavServerNotSupported, .webdavServerNotSupported): return true
        case (.webdavDownloadFailed(let a), .webdavDownloadFailed(let b)): return a == b
        case (.webdavCertificateError, .webdavCertificateError): return true
        case (.lyricsSearchFailed(let a), .lyricsSearchFailed(let b)): return a == b
        case (.lyricsSaveFailed(let a), .lyricsSaveFailed(let b)): return a == b
        case (.lyricsImportFailed(let a), .lyricsImportFailed(let b)): return a == b
        case (.lyricsDeleteFailed(let a), .lyricsDeleteFailed(let b)): return a == b
        case (.fileSystemError(let a), .fileSystemError(let b)): return a == b
        case (.imageProcessingFailed(let a), .imageProcessingFailed(let b)): return a == b
        case (.purchaseFailed(let a), .purchaseFailed(let b)): return a == b
        case (.featureRequiresPremium(let a), .featureRequiresPremium(let b)): return a == b
        case (.backupInvalidPackage(let a), .backupInvalidPackage(let b)): return a == b
        case (.backupUnsupportedVersion(let a), .backupUnsupportedVersion(let b)): return a == b
        case (.backupCancelled, .backupCancelled): return true
        case (.backupCommitRolledBack(let a), .backupCommitRolledBack(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - CaseIterable
extension AppError: CaseIterable {
    /// 含关联值的枚举无法由编译器合成 CaseIterable；此处为测试与完整性检查提供代表性实例。
    /// `expectedCaseCount` 与此列表长度在单元测试中交叉验证，新增 case 时两处须同步更新。
    static let expectedCaseCount = 39

    static var allCases: [AppError] {
        let id = UUID()
        return [
            .importUnsupportedFormat("test"),
            .importFileTooLarge(1024),
            .importFileCorrupted("test"),
            .importReadFailed("test"),
            .importDuplicate("test"),
            .playbackFileNotFound(id),
            .playbackFileCorrupted(id),
            .playbackUnsupportedFormat("flac"),
            .playbackSessionFailed,
            .playbackLoadFailed("test"),
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
            .playQueueFull,
            .webdavConnectionFailed("test"),
            .webdavAuthFailed,
            .webdavServerNotSupported,
            .webdavDownloadFailed("test"),
            .webdavCertificateError,
            .lyricsSearchFailed("test"),
            .lyricsSaveFailed("test"),
            .lyricsImportFailed("test"),
            .lyricsDeleteFailed("test"),
            .fileSystemError("test"),
            .imageProcessingFailed("test"),
            .purchaseFailed("test"),
            .featureRequiresPremium("losslessPlayback"),
            .backupInvalidPackage("test"),
            .backupUnsupportedVersion(99),
            .backupCancelled,
            .backupCommitRolledBack("test"),
        ]
    }
}

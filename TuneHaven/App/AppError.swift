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
        }
    }
}

// MARK: - Equatable（用于 Swift Testing #expect(throws:) 精确值比较）
extension AppError: Equatable {
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.errorCode == rhs.errorCode
    }
}

final class ErrorLogger {
    static let shared = ErrorLogger()
    private let maxFileSize: Int64 = 5 * 1024 * 1024
    private let writeQueue = DispatchQueue(label: "com.tunehaven.errorlogger", qos: .utility)

    private var logFileURL: URL {
        SandboxPathManager.documentsURL.appendingPathComponent("error.log")
    }

    private init() {}

    func log(_ error: AppError, context: String, file: String = #file, line: Int = #line) {
        let shortFile = (file as NSString).lastPathComponent
        let entry = "[\(isoDate())] [\(error.errorCode)] \(context) - \(error.localizedDescription) at \(shortFile):\(line)\n"
        appendToLog(entry)
    }

    func logGeneric(_ error: Error, context: String) {
        let entry = "[\(isoDate())] [GEN] \(context) - \(error.localizedDescription)\n"
        appendToLog(entry)
    }

    private func appendToLog(_ entry: String) {
        guard let data = entry.data(using: .utf8) else { return }
        let url = logFileURL
        writeQueue.async {
            self.rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int64) ?? 0
        if size > maxFileSize {
            let backupURL = logFileURL.deletingLastPathComponent().appendingPathComponent("error.log.old")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: logFileURL, to: backupURL)
        }
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func isoDate() -> String {
        Self.dateFormatter.string(from: Date())
    }
}

// MARK: - AppLogger

enum LogLevel: String {
    case debug = "DEBUG"
    case info  = "INFO"
    case error = "ERROR"
}

final class AppLogger {
    static let shared = AppLogger()
    private let maxFileSize: Int64 = 5 * 1024 * 1024
    private let writeQueue = DispatchQueue(label: "com.tunehaven.applogger", qos: .utility)

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var logFileURL: URL {
        SandboxPathManager.documentsURL.appendingPathComponent("app.log")
    }

    private init() {}

    func debug(_ message: String, file: String = #file, function: String = #function) {
        writeLog(level: .debug, message: message, file: file, function: function)
    }

    func info(_ message: String, file: String = #file, function: String = #function) {
        writeLog(level: .info, message: message, file: file, function: function)
    }

    func error(_ message: String, file: String = #file, function: String = #function) {
        writeLog(level: .error, message: message, file: file, function: function)
    }

    func error(_ err: Error, context: String, file: String = #file, function: String = #function) {
        let msg = "\(context) - \(err.localizedDescription)"
        writeLog(level: .error, message: msg, file: file, function: function)
    }

    func error(_ err: AppError, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        let msg = "[\(err.errorCode)] \(context) - \(err.localizedDescription)"
        writeLog(level: .error, message: msg, file: file, function: function)
        ErrorLogger.shared.log(err, context: context, file: file, line: line)
    }

    private func writeLog(level: LogLevel, message: String, file: String, function: String) {
        let shortFile = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        let entry = "[\(Self.dateFormatter.string(from: Date()))] [\(level.rawValue)] [\(shortFile).\(function)] \(message)\n"
        #if DEBUG
        print(entry, terminator: "")
        #endif
        appendToFile(entry)
    }

    private func appendToFile(_ entry: String) {
        guard let data = entry.data(using: .utf8) else { return }
        let url = logFileURL
        writeQueue.async {
            self.rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int64) ?? 0
        if size > maxFileSize {
            let backupURL = logFileURL.deletingLastPathComponent().appendingPathComponent("app.log.old")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: logFileURL, to: backupURL)
        }
    }
}

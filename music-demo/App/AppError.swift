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
        rotateIfNeeded()
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL)
        }
    }

    private func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int64) ?? 0
        if size > maxFileSize {
            try? FileManager.default.removeItem(at: logFileURL)
        }
    }

    private func isoDate() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

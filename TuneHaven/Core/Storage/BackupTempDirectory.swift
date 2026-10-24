import Foundation

/// 备份用的三个 tmp 目录。系统不会在进程还活着时清掉它们，连续导出或外部打开会把包留在这里。
struct BackupTempDirectory: Equatable, Sendable {
    var export: URL
    var incoming: URL
    var extract: URL

    static var live: BackupTempDirectory {
        BackupTempDirectory(
            export: SandboxPathManager.backupExportURL,
            incoming: SandboxPathManager.backupIncomingURL,
            extract: SandboxPathManager.backupExtractURL
        )
    }

    /// 冷启动清理。同步返回，调用方必须在任何导出或系统分享开始之前做完。
    /// 只删除这三个目录里的内容，目录本身和其他 tmp 目录不动。
    @discardableResult
    static func cleanupOnLaunch(
        _ directory: BackupTempDirectory = .live,
        fileManager: FileManager = .default
    ) -> Int {
        removeContents(of: directory.export, fileManager: fileManager)
            + removeContents(of: directory.incoming, fileManager: fileManager)
            + removeContents(of: directory.extract, fileManager: fileManager)
    }

    /// 删除目录中的直接子项。目录不存在时什么也不做。`keeping` 指向的文件会留下。
    @discardableResult
    static func removeContents(
        of directory: URL,
        keeping kept: URL? = nil,
        fileManager: FileManager = .default
    ) -> Int {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return 0
        }
        let items: [URL]
        do {
            items = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            ErrorLogger.shared.logGeneric(error, context: "无法列出备份临时目录")
            return 0
        }
        var removed = 0
        for item in items {
            if let kept, sameFile(item, kept) { continue }
            do {
                try fileManager.removeItem(at: item)
                removed += 1
            } catch {
                ErrorLogger.shared.logGeneric(error, context: "备份临时文件清理失败")
            }
        }
        return removed
    }

    /// `url` 是否是 `directory` 里面的文件或子目录，而不是目录本身。
    static func containsFile(_ url: URL, in directory: URL) -> Bool {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }

    static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

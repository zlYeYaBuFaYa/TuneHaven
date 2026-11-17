import Foundation

/// 备份与导入互相排队。任一任务进行中时，另一任务直接失败，避免同时改曲库。
final class BackupActivityGate: @unchecked Sendable {
    private let lock = NSLock()
    private var backupBusy = false
    private var importBusy = false

    func beginBackup() throws {
        try begin(asBackup: true)
    }

    func endBackup() {
        lock.lock()
        backupBusy = false
        lock.unlock()
    }

    /// 备份或导入正在进行。此时 `beginImport` / `beginBackup` 会失败
    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return backupBusy || importBusy
    }

    func beginImport() throws {
        try begin(asBackup: false)
    }

    func endImport() {
        lock.lock()
        importBusy = false
        lock.unlock()
    }

    private func begin(asBackup: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        if backupBusy || importBusy {
            throw AppError.fileSystemError("已有导入或备份任务正在进行")
        }
        if asBackup {
            backupBusy = true
        } else {
            importBusy = true
        }
    }
}

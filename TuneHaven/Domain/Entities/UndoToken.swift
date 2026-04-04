import Foundation

/// 撤销删除的令牌。使用 class 以支持可变的 timerKey 状态，
/// 由 MusicLibraryService 管理生命周期（定时器关联、过期清理）。
class UndoToken: @unchecked Sendable {
    struct MovedFile {
        let tempPath: String
        let originalRelativePath: String
    }
    let songIds: [UUID]
    let movedFiles: [MovedFile]
    let expiresAt: Date
    var timerKey: UUID?

    init(songIds: [UUID], movedFiles: [MovedFile], expiresAt: Date) {
        self.songIds = songIds
        self.movedFiles = movedFiles
        self.expiresAt = expiresAt
    }
}

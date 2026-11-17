import SwiftUI

@MainActor
enum SongDeletionHelper {
    static func softDelete(
        song: Song,
        libraryService: MusicLibraryService,
        snackbar: SnackbarState
    ) {
        Task {
            do {
                let token = try await libraryService.softDelete(songIds: [song.id])
                snackbar.show(
                    message: "已删除《\(song.title)》",
                    actionTitle: "撤销",
                    action: {
                        Task {
                            do {
                                try await libraryService.undoDelete(token: token)
                            } catch {
                                snackbar.show(message: "撤销删除失败，请重试")
                            }
                        }
                    },
                    duration: 30
                )
            } catch {
                snackbar.show(message: "删除失败，请重试")
            }
        }
    }
}

/// 「下一首播放」的统一入口：成功才提示，队列满时明确告知（交互设计文档 §4.3、§11）
@MainActor
enum SongQueueHelper {
    static func insertNext(song: Song, playback: PlaybackService, snackbar: SnackbarState) {
        switch playback.queue.insertNext(song) {
        case .success:
            snackbar.show(message: "已添加到下一首播放")
        case .queueFull:
            snackbar.show(message: "播放队列已满，请先移除一些歌曲")
        }
    }
}

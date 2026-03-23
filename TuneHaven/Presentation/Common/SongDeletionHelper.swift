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
                    }
                )
            } catch {
                snackbar.show(message: "删除失败，请重试")
            }
        }
    }
}

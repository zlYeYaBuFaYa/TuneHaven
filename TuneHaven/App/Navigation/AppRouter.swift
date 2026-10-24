import SwiftUI

struct ExternalBackupHandoff: Equatable, Sendable {
    var token: Int
    /// 播放器、其它 sheet，或上一次打开还在等动画时为 true。
    var needsDelay: Bool
    /// 全屏播放器当时还在。先收起它自己的 sheet，再收起播放器。
    var playerWasPresented: Bool
}

enum AppTab: Int, CaseIterable {
    case library = 0
    case playlist = 1
    case settings = 2
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var libraryPath  = NavigationPath()
    @Published var playlistPath = NavigationPath()
    @Published var settingsPath = NavigationPath()
    @Published var selectedTab: AppTab = .library
    @Published var sheet: SheetDestination?
    @Published var isPlayerPresented = false
    /// 从文件打开备份时递增，让播放器收起自己的 sheet。不停止播放。
    @Published private(set) var playerModalReset = 0
    /// 为 true 时，延迟弹出的付费墙让出唯一的模态层。订阅门禁本身不在这里改变。
    private(set) var externalBackupTakesModal = false
    private var externalBackupToken = 0

    /// 播放器 sheet 和全屏页收起后，再等这么久才弹恢复页。长于付费墙的 0.35 秒延迟。
    static let externalBackupDismissSettle: Duration = .milliseconds(500)

    func navigate(to destination: AppDestination, in tab: AppTab? = nil) {
        let targetTab = tab ?? selectedTab
        selectedTab = targetTab
        switch targetTab {
        case .library:  libraryPath.append(destination)
        case .playlist: playlistPath.append(destination)
        case .settings: settingsPath.append(destination)
        }
    }

    func popToRoot(in tab: AppTab? = nil) {
        switch tab ?? selectedTab {
        case .library:  libraryPath  = NavigationPath()
        case .playlist: playlistPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        }
    }

    func present(_ sheet: SheetDestination) { self.sheet = sheet }
    func dismissSheet() { sheet = nil }

    func openPlayer() {
        isPlayerPresented = true
    }

    /// 只收起全屏页，不暂停、不停止播放。
    func closePlayer() {
        isPlayerPresented = false
    }

    /// 从「文件」打开备份前调用。立刻收起根 sheet，并请播放器收起自己的 sheet。
    /// 播放器当时开着时，调用方要等动画结束后再 `closePlayer()`。
    func relinquishModalsForExternalBackup() -> ExternalBackupHandoff {
        let handoffInProgress = externalBackupTakesModal
        let playerWasPresented = isPlayerPresented
        let sheetWasPresented = sheet != nil
        externalBackupToken += 1
        externalBackupTakesModal = true
        if playerWasPresented {
            playerModalReset += 1
        }
        sheet = nil
        return ExternalBackupHandoff(
            token: externalBackupToken,
            needsDelay: playerWasPresented || sheetWasPresented || handoffInProgress,
            playerWasPresented: playerWasPresented
        )
    }

    func isCurrentExternalBackup(_ token: Int) -> Bool {
        externalBackupTakesModal && token == externalBackupToken
    }

    func finishExternalBackupPresentation() {
        externalBackupTakesModal = false
    }
}

import SwiftUI

struct ExternalBackupHandoff: Equatable, Sendable {
    var token: Int
    /// 播放器、其它 sheet，或上一次打开还在等动画时为 true。
    var needsDelay: Bool
    /// 全屏播放器当时还在。先收起它自己的 sheet，再收起播放器。
    var playerWasPresented: Bool
}

enum ExternalBackupShowResult: Equatable, Sendable {
    /// 可以弹恢复页。
    case present
    /// 全屏播放器或根 sheet 还在。本次不弹，模态标志已经复位。
    case abandonModalOccupied
    /// 这次打开已经作废，或标志不在这次上。调用方不要再改状态。
    case superseded
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
    /// 这次打开的恢复页已经 `onAppear`。超时兜底只认这个标记。
    /// 调用 `presentRestore` 不算，否则被 Tab 里的局部 sheet 挡住时会整段会话占着模态层。
    private var externalBackupPresentedToken: Int?

    /// 播放器 sheet 和全屏页收起后，再等这么久才弹恢复页。长于付费墙的 0.35 秒延迟。
    static let externalBackupDismissSettle: Duration = .milliseconds(500)
    /// 标志置位后，若这次打开还没弹出恢复页，就放开模态层。必须长于两段收起等待。
    static let externalBackupPresentationTimeout: Duration = .seconds(3)

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
        externalBackupPresentedToken = nil
    }

    /// 全屏播放器或根 sheet。恢复页自己的 sheet 不算，否则替换正在看的包会被当成抢占。
    private var otherModalBlocksExternalBackup: Bool {
        isPlayerPresented || sheet != nil
    }

    /// 交接结束、准备弹恢复页时调用。已有别的模态就放弃本次并立刻复位。
    /// 不在模态都关掉之后再弹，避免和超时兜底、以及用户接下来打开的页面再抢一次。
    func resolveExternalBackupShow(token: Int) -> ExternalBackupShowResult {
        guard isCurrentExternalBackup(token) else { return .superseded }
        if otherModalBlocksExternalBackup {
            finishExternalBackupPresentation()
            return .abandonModalOccupied
        }
        return .present
    }

    /// 恢复页 `onAppear` 时调用。token 不是当前这次打开时什么都不做。
    func confirmExternalBackupAppeared(token: Int) {
        guard isCurrentExternalBackup(token) else { return }
        externalBackupPresentedToken = token
    }

    /// 标志已经置位，但这份恢复页还没出现。后一次打开或已经出现的页面不动。
    /// 返回 true 表示这次确实放开了模态层，调用方再提示并保留 incoming 副本。
    @discardableResult
    func releaseExternalBackupIfNotPresented(token: Int) -> Bool {
        guard isCurrentExternalBackup(token) else { return false }
        guard externalBackupPresentedToken != token else { return false }
        finishExternalBackupPresentation()
        return true
    }

    /// 从标志置位开始计时。任务被取消时不复位，避免测试或提前结束把一次正常打开清掉。
    /// 真正放开时才调用 `onReleased`。提示和撤回未出现的恢复页放在那个回调里，路由本身不依赖它们。
    @discardableResult
    func scheduleExternalBackupPresentationTimeout(
        token: Int,
        timeout: Duration = AppRouter.externalBackupPresentationTimeout,
        onReleased: (@MainActor () -> Void)? = nil
    ) -> Task<Void, Never> {
        return Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self else { return }
            guard self.releaseExternalBackupIfNotPresented(token: token) else { return }
            onReleased?()
        }
    }
}

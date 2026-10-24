import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("从文件打开备份时的模态调度")
struct BackupOpenRoutingTests {
    @Test("没有其它页面时不需要等待")
    func testIdleHandoffPresentsImmediately() {
        let router = AppRouter()
        let handoff = router.relinquishModalsForExternalBackup()
        #expect(handoff.needsDelay == false)
        #expect(handoff.playerWasPresented == false)
        #expect(handoff.token == 1)
        #expect(router.externalBackupTakesModal)
        #expect(router.isCurrentExternalBackup(handoff.token))
        #expect(router.playerModalReset == 0)
        #expect(router.isPlayerPresented == false)
        #expect(router.sheet == nil)
    }

    @Test("全屏播放器先留着，只请它收起自己的 sheet")
    func testPlayerStaysPresentedUntilCallerClosesIt() {
        let router = AppRouter()
        router.openPlayer()
        router.present(.paywall(feature: .losslessPlayback))
        let handoff = router.relinquishModalsForExternalBackup()
        #expect(handoff.needsDelay)
        #expect(handoff.playerWasPresented)
        #expect(router.isPlayerPresented)
        #expect(router.sheet == nil)
        #expect(router.playerModalReset == 1)
        #expect(router.externalBackupTakesModal)
        router.closePlayer()
        #expect(router.isPlayerPresented == false)
    }

    @Test("只有根 sheet 时会等它收起，但不碰播放器")
    func testRootSheetDismissesWithoutClosingPlayer() {
        let router = AppRouter()
        router.present(.importFromFiles)
        let handoff = router.relinquishModalsForExternalBackup()
        #expect(handoff.needsDelay)
        #expect(handoff.playerWasPresented == false)
        #expect(router.sheet == nil)
        #expect(router.playerModalReset == 0)
        #expect(router.isPlayerPresented == false)
    }

    @Test("后一次打开作废前一次，进行中的交接也要等待")
    func testNewerOpenSupersedesInFlightHandoff() {
        let router = AppRouter()
        router.openPlayer()
        let first = router.relinquishModalsForExternalBackup()
        router.closePlayer()
        let second = router.relinquishModalsForExternalBackup()
        #expect(first.needsDelay)
        #expect(second.needsDelay)
        #expect(router.isCurrentExternalBackup(first.token) == false)
        #expect(router.isCurrentExternalBackup(second.token))
        #expect(second.playerWasPresented == false)
    }

    @Test("恢复页关闭后付费墙可以再次占用模态层")
    func testFinishReleasesModalForPaywall() {
        let router = AppRouter()
        router.present(.setSleepTimer)
        let handoff = router.relinquishModalsForExternalBackup()
        #expect(router.externalBackupTakesModal)
        router.finishExternalBackupPresentation()
        #expect(router.externalBackupTakesModal == false)
        #expect(router.isCurrentExternalBackup(handoff.token) == false)
        router.present(.paywall(feature: .losslessPlayback))
        #expect(router.sheet?.id == SheetDestination.paywall(feature: .losslessPlayback).id)
    }

    @Test("收起动画等待长于付费墙延迟，弹出兜底又长于整段交接")
    func testDismissSettleOutlastsPaywallDelay() {
        #expect(AppRouter.externalBackupDismissSettle > .milliseconds(350))
        #expect(AppRouter.externalBackupPresentationTimeout == .seconds(3))
        #expect(AppRouter.externalBackupPresentationTimeout > .seconds(1))
    }

    @Test("交接窗口里重新打开播放器：放弃弹出、标志复位、副本保留")
    func testHandoffPlayerPreemptAbandonsAndKeepsCopy() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let source = try fixture.makePackage()
        let staged = try #require(fixture.service.stageExternalPackage(source))
        let router = AppRouter()
        let snackbar = SnackbarState()
        router.present(.importFromFiles)
        let handoff = router.relinquishModalsForExternalBackup()
        #expect(handoff.needsDelay)
        #expect(handoff.playerWasPresented == false)
        let timeoutTask = ExternalBackupOpen.begin(
            url: staged,
            handoff: handoff,
            router: router,
            backupService: fixture.service,
            snackbar: snackbar,
            settle: .milliseconds(20),
            presentationTimeout: .seconds(2)
        )
        defer { timeoutTask.cancel() }
        // 先占住播放器再让出主线程。交接任务要等这次调用挂起才开始等待。
        router.openPlayer()
        await waitUntil { snackbar.message == ExternalBackupOpen.modalOccupiedNotice }

        #expect(snackbar.message == ExternalBackupOpen.modalOccupiedNotice)
        #expect(router.externalBackupTakesModal == false)
        #expect(router.isCurrentExternalBackup(handoff.token) == false)
        #expect(router.isPlayerPresented)
        #expect(fixture.service.presentation == nil)
        #expect(fixture.service.shouldReleaseExternalModal == false)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
        router.present(.paywall(feature: .losslessPlayback))
        #expect(router.sheet?.id == SheetDestination.paywall(feature: .losslessPlayback).id)
    }

    @Test("交接窗口里点开付费墙：放弃弹出、标志复位、副本留到冷启动")
    func testHandoffPaywallPreemptAbandonsAndColdStartRemovesCopy() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let source = try fixture.makePackage()
        let staged = try #require(fixture.service.stageExternalPackage(source))
        let router = AppRouter()
        let snackbar = SnackbarState()
        router.openPlayer()
        let handoff = router.relinquishModalsForExternalBackup()
        #expect(handoff.needsDelay)
        #expect(handoff.playerWasPresented)
        let timeoutTask = ExternalBackupOpen.begin(
            url: staged,
            handoff: handoff,
            router: router,
            backupService: fixture.service,
            snackbar: snackbar,
            settle: .milliseconds(20),
            presentationTimeout: .seconds(2)
        )
        defer { timeoutTask.cancel() }
        router.present(.paywall(feature: nil))
        await waitUntil { snackbar.message == ExternalBackupOpen.modalOccupiedNotice }

        #expect(router.externalBackupTakesModal == false)
        #expect(router.isPlayerPresented == false)
        #expect(router.sheet?.id == SheetDestination.paywall(feature: nil).id)
        #expect(fixture.service.presentation == nil)
        #expect(fixture.service.shouldReleaseExternalModal == false)
        #expect(FileManager.default.fileExists(atPath: staged.path))

        // 设置里的「从备份恢复」关掉时，也不能把这份还没弹出的副本删掉。
        fixture.service.presentRestore(url: nil)
        dismissBackupSheet(service: fixture.service, router: router)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(router.externalBackupTakesModal == false)
        #expect(FileManager.default.fileExists(atPath: source.path))
        BackupTempDirectory.cleanupOnLaunch(fixture.directories)
        #expect(FileManager.default.fileExists(atPath: staged.path) == false)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("放弃后关掉旧恢复页，不会删掉还没弹出的副本")
    func testAbandonKeepsPendingCopyWhenOldRestoreDismisses() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let first = try #require(fixture.service.stageExternalPackage(try fixture.makePackage()))
        fixture.service.presentRestore(url: first)
        let second = try #require(fixture.service.stageExternalPackage(try fixture.makePackage()))
        let router = AppRouter()
        let snackbar = SnackbarState()
        router.openPlayer()
        let handoff = router.relinquishModalsForExternalBackup()
        ExternalBackupOpen.attemptShow(
            url: second,
            token: handoff.token,
            router: router,
            backupService: fixture.service,
            snackbar: snackbar
        )

        #expect(snackbar.message == ExternalBackupOpen.modalOccupiedNotice)
        #expect(router.externalBackupTakesModal == false)
        #expect(fixture.service.presentation?.packageURL?.path == first.path)
        dismissBackupSheet(service: fixture.service, router: router)
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: first.path) == false)
        #expect(router.externalBackupTakesModal == false)
    }

    @Test("空闲时仍然马上弹出，关闭后删除副本并放开标志")
    func testIdleOpenStillPresentsAndDismissDeletesCopy() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let staged = try #require(fixture.service.stageExternalPackage(try fixture.makePackage()))
        let router = AppRouter()
        let snackbar = SnackbarState()
        let handoff = router.relinquishModalsForExternalBackup()
        #expect(handoff.needsDelay == false)
        let timeoutTask = ExternalBackupOpen.begin(
            url: staged,
            handoff: handoff,
            router: router,
            backupService: fixture.service,
            snackbar: snackbar,
            presentationTimeout: .milliseconds(30)
        )
        #expect(fixture.service.presentation?.kind == .restore)
        #expect(fixture.service.presentation?.packageURL?.path == staged.path)
        #expect(fixture.service.shouldReleaseExternalModal)
        #expect(router.externalBackupTakesModal)
        #expect(snackbar.message.isEmpty)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        await timeoutTask.value
        #expect(router.externalBackupTakesModal)
        dismissBackupSheet(service: fixture.service, router: router)
        #expect(fixture.service.presentation == nil)
        #expect(FileManager.default.fileExists(atPath: staged.path) == false)
        #expect(router.externalBackupTakesModal == false)
    }

    @Test("播放器收起后的正常交接仍会弹出，且不关掉后来的付费墙占用")
    func testPlayerHandoffStillPresentsWhenNothingElseOpens() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let staged = try #require(fixture.service.stageExternalPackage(try fixture.makePackage()))
        let router = AppRouter()
        let snackbar = SnackbarState()
        router.openPlayer()
        let handoff = router.relinquishModalsForExternalBackup()
        let timeoutTask = ExternalBackupOpen.begin(
            url: staged,
            handoff: handoff,
            router: router,
            backupService: fixture.service,
            snackbar: snackbar,
            settle: .milliseconds(20),
            presentationTimeout: .seconds(2)
        )
        defer { timeoutTask.cancel() }
        await waitUntil { fixture.service.presentation?.kind == .restore }

        #expect(fixture.service.presentation?.packageURL?.path == staged.path)
        #expect(router.isPlayerPresented == false)
        #expect(router.externalBackupTakesModal)
        #expect(router.isCurrentExternalBackup(handoff.token))
        #expect(snackbar.message.isEmpty)
        #expect(fixture.service.shouldReleaseExternalModal)
        router.present(.paywall(feature: .losslessPlayback))
        router.releaseExternalBackupIfNotPresented(token: handoff.token)
        #expect(router.externalBackupTakesModal)
    }

    @Test("后一次打开作废后，前一次 show 不弹页、不提示、不清掉新标志")
    func testSupersededShowLeavesNewerHandoffAlone() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let staged = try #require(fixture.service.stageExternalPackage(try fixture.makePackage()))
        let router = AppRouter()
        let snackbar = SnackbarState()
        router.openPlayer()
        let first = router.relinquishModalsForExternalBackup()
        router.closePlayer()
        let second = router.relinquishModalsForExternalBackup()
        ExternalBackupOpen.attemptShow(
            url: staged,
            token: first.token,
            router: router,
            backupService: fixture.service,
            snackbar: snackbar
        )
        #expect(snackbar.message.isEmpty)
        #expect(fixture.service.presentation == nil)
        #expect(router.externalBackupTakesModal)
        #expect(router.isCurrentExternalBackup(second.token))
        #expect(FileManager.default.fileExists(atPath: staged.path))
        router.releaseExternalBackupIfNotPresented(token: first.token)
        #expect(router.isCurrentExternalBackup(second.token))
    }

    @Test("未弹出时兜底复位并保留副本；已经弹出或任务取消则不动")
    func testTimeoutReleasesOnlyWhenRestoreNeverPresented() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let staged = try #require(fixture.service.stageExternalPackage(try fixture.makePackage()))
        let router = AppRouter()
        let missing = router.relinquishModalsForExternalBackup()
        router.releaseExternalBackupIfNotPresented(token: missing.token)
        #expect(router.externalBackupTakesModal == false)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(fixture.service.presentation == nil)

        let timed = router.relinquishModalsForExternalBackup()
        let timeoutTask = router.scheduleExternalBackupPresentationTimeout(
            token: timed.token,
            timeout: .milliseconds(20)
        )
        await timeoutTask.value
        #expect(router.externalBackupTakesModal == false)
        #expect(FileManager.default.fileExists(atPath: staged.path))

        let presented = router.relinquishModalsForExternalBackup()
        router.markExternalBackupPresented(token: presented.token)
        let keepTask = router.scheduleExternalBackupPresentationTimeout(
            token: presented.token,
            timeout: .milliseconds(20)
        )
        await keepTask.value
        #expect(router.isCurrentExternalBackup(presented.token))
        #expect(FileManager.default.fileExists(atPath: staged.path))

        let cancelled = router.relinquishModalsForExternalBackup()
        let cancelTask = router.scheduleExternalBackupPresentationTimeout(
            token: cancelled.token,
            timeout: .seconds(30)
        )
        cancelTask.cancel()
        await cancelTask.value
        #expect(router.isCurrentExternalBackup(cancelled.token))

        let newer = router.relinquishModalsForExternalBackup()
        let staleTask = router.scheduleExternalBackupPresentationTimeout(
            token: cancelled.token,
            timeout: .milliseconds(20)
        )
        await staleTask.value
        #expect(router.isCurrentExternalBackup(newer.token))
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ ready: @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !ready() && clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func dismissBackupSheet(service: BackupRestoreService, router: AppRouter) {
    service.handlePresentationChange(to: nil)
    if service.shouldReleaseExternalModal {
        router.finishExternalBackupPresentation()
    }
}

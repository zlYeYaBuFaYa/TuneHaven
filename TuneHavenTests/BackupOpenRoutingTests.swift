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

    @Test("收起动画等待长于付费墙延迟")
    func testDismissSettleOutlastsPaywallDelay() {
        #expect(AppRouter.externalBackupDismissSettle > .milliseconds(350))
    }
}

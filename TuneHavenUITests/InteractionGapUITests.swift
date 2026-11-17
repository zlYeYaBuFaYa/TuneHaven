import XCTest

final class InteractionGapUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testAccessibleLyricsCanReachRetryAndPlayback() {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEHAVEN_DEBUG_ROUTE"] = "player.lyrics"
        app.launchEnvironment["TUNEHAVEN_DEBUG_LYRICS_STATE"] = "networkError"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let retry = app.buttons["lyrics.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        for _ in 0..<8 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.isHittable)
        attach(app, name: "lyrics-ax5-retry")
        let play = app.buttons["player.playPause"]
        for _ in 0..<8 where !play.isHittable { app.swipeUp() }
        XCTAssertTrue(play.isHittable)
        attach(app, name: "lyrics-ax5-controls")
    }

    @MainActor
    func testPlaylistOrderHasTapAlternative() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEHAVEN_SEED_DIR"] = try makeSeedAudio().path
        app.launchEnvironment["TUNEHAVEN_DEBUG_ROUTE"] = "playlist"
        app.launch()
        let edit = app.buttons["调整歌单顺序"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        if !edit.isHittable { app.swipeUp() }
        edit.tap()
        let moves = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "调整顺序："))
        XCTAssertTrue(moves.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(moves.count, 1)
        let second = moves.element(boundBy: 1).label
        moves.firstMatch.tap()
        XCTAssertFalse(app.buttons["上移"].isEnabled)
        app.buttons["下移"].tap()
        expectation(for: NSPredicate(format: "label == %@", second), evaluatedWith: moves.firstMatch)
        waitForExpectations(timeout: 5)
        attach(app, name: "playlist-order-tap-alternative")
    }

    @MainActor
    func testSongOrderCancelAndSave() throws {
        let app = XCUIApplication()
        let seed = try makeSeedAudio()
        app.launchEnvironment["TUNEHAVEN_SEED_DIR"] = seed.path
        app.launchEnvironment["TUNEHAVEN_DEBUG_ROUTE"] = "playlist.detail"
        app.launch()
        let actions = app.buttons["歌单操作"]
        XCTAssertTrue(actions.waitForExistence(timeout: 20))
        func openOrder() {
            actions.tap()
            app.buttons["调整歌曲顺序"].tap()
            XCTAssertTrue(app.navigationBars["调整歌曲顺序"].waitForExistence(timeout: 5))
        }
        openOrder()
        let moves = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "调整顺序："))
        XCTAssertTrue(moves.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(moves.count, 1)
        let first = moves.element(boundBy: 0).label
        let second = moves.element(boundBy: 1).label
        let save = app.buttons["playlist.order.save"]
        XCTAssertFalse(save.isEnabled)
        moves.firstMatch.tap()
        XCTAssertFalse(app.buttons["上移"].isEnabled)
        app.buttons["下移"].tap()
        XCTAssertEqual(moves.firstMatch.label, second)
        XCTAssertTrue(save.isEnabled)
        app.navigationBars["调整歌曲顺序"].buttons["取消"].tap()
        openOrder()
        XCTAssertEqual(moves.firstMatch.label, first)
        moves.firstMatch.tap()
        app.buttons["下移"].tap()
        save.tap()
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        openOrder()
        XCTAssertEqual(moves.firstMatch.label, second)
        XCTAssertFalse(save.isEnabled)
        attach(app, name: "song-order-saved")
    }

    @MainActor
    func testLyricsStatesKeepLocalActionsAvailable() {
        for (state, title, retry) in [("matching", "正在匹配歌词", false),
                                      ("networkError", "暂时无法匹配歌词", true),
                                      ("notFound", "没有找到匹配歌词", false),
                                      ("instrumental", "器乐曲（无歌词）", false)] {
            let app = XCUIApplication()
            app.launchEnvironment["TUNEHAVEN_DEBUG_ROUTE"] = "player.lyrics"
            app.launchEnvironment["TUNEHAVEN_DEBUG_LYRICS_STATE"] = state
            app.launch()
            let status = app.staticTexts["lyrics.status"]
            XCTAssertTrue(status.waitForExistence(timeout: 15))
            XCTAssertEqual(status.label, title)
            XCTAssertTrue(app.buttons["导入 LRC"].exists)
            XCTAssertEqual(app.buttons["lyrics.retry"].exists, retry)
            if retry {
                app.buttons["lyrics.retry"].tap()
                XCTAssertTrue(status.exists)
            }
            attach(app, name: "lyrics-\(state)")
            app.terminate()
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeSeedAudio() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("interaction-seed", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Four one-second silent PCM WAVs, generated locally for a fresh simulator library.
        func little(_ n: Int, bytes: Int) -> Data { Data((0..<bytes).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
        let payload = Data(repeating: 0, count: 16000)
        var wav = Data("RIFF".utf8)
        wav += little(payload.count + 36, bytes: 4)
        wav += Data("WAVEfmt ".utf8)
        for (value, bytes) in [(16, 4), (1, 2), (1, 2), (8000, 4), (16000, 4), (2, 2), (16, 2)] {
            wav += little(value, bytes: bytes)
        }
        wav += Data("data".utf8)
        wav += little(payload.count, bytes: 4)
        wav += payload
        for i in 1...4 {
            var distinct = wav
            distinct[44] = UInt8(i)
            try distinct.write(to: root.appendingPathComponent("交互测试\(i).wav"))
        }
        return root
    }
}

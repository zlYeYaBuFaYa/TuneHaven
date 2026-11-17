import XCTest

final class ShareFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testShareSelectionDoesNotBeginTransferBeforeConfirmingSongs() {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEHAVEN_DEBUG_ROUTE"] = "share.send"
        app.launch()
        let songs = app.buttons["share.send.songs"]
        XCTAssertTrue(songs.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["share.send.playlists"].exists)
        songs.tap()
        XCTAssertTrue(app.navigationBars["选择歌曲"].waitForExistence(timeout: 5))
        let send = app.buttons["开始分享"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)
        XCTAssertFalse(app.staticTexts["等待连接..."].exists)
    }
}

import XCTest

final class ImportFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testLibraryHubOpensCloudAndReturnsWithoutRequestingMediaAccess() {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEHAVEN_DEBUG_ROUTE"] = "import"
        app.launch()
        let cloud = app.buttons["import.source.cloudDrive"]
        XCTAssertTrue(cloud.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["import.source.appleMusic"].exists)
        cloud.tap()
        XCTAssertTrue(app.navigationBars["云盘导入"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.navigationBars["云盘导入"].buttons["关闭"].tap()
        XCTAssertTrue(cloud.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["文件选择失败"].exists)
    }

    @MainActor
    func testCancellingFilesPickerReturnsToHubWithoutFailure() {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEHAVEN_DEBUG_ROUTE"] = "import"
        app.launch()
        let files = app.buttons["import.source.files"]
        XCTAssertTrue(files.waitForExistence(timeout: 15))
        files.tap()
        let cancel = app.buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "文件选择失败")).firstMatch.exists)
    }

    @MainActor
    func testSettingsWifiShortcutUsesSameHubAndDoesNotStartServer() {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEHAVEN_DEBUG_ROUTE"] = "settings.open"
        app.launch()
        let wifi = app.buttons["settings.import.wifi"]
        XCTAssertTrue(wifi.waitForExistence(timeout: 15))
        if !wifi.isHittable { app.swipeUp() }
        wifi.tap()
        XCTAssertTrue(app.navigationBars["WiFi 传输"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.switches["开启传输服务"].exists)
        app.navigationBars["WiFi 传输"].buttons["关闭"].tap()
        XCTAssertTrue(app.buttons["import.source.wifi"].waitForExistence(timeout: 5))
    }
}

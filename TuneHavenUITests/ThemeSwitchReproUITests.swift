import XCTest

/// 在设置页反复切换 4 套主题，检查界面不消失（白屏回归）。
final class ThemeSwitchReproUITests: XCTestCase {

    @MainActor
    func testRepeatedThemeSwitchKeepsUIVisible() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()

        let settingsTab = app.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 40))
        settingsTab.tap()

        let appearance = app.buttons["外观"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        appearance.tap()

        let themes = ["星际穹顶", "素云白简", "暮光玫瑰", "晴空蔚蓝"]
        XCTAssertTrue(app.buttons[themes[0]].waitForExistence(timeout: 10))

        for round in 0..<3 {
            for name in themes {
                let card = app.buttons[name]
                guard card.waitForExistence(timeout: 5) else {
                    attach(app, "missing-\(round)-\(name)")
                    XCTFail("找不到主题卡片 \(name)（第 \(round) 轮）")
                    return
                }
                card.tap()
                // 覆盖 setTheme 后 0.3 秒的窗口刷新
                Thread.sleep(forTimeInterval: 0.8)
                attach(app, "after-\(round)-\(name)")
                XCTAssertTrue(app.buttons["外观"].isHittable, "切到 \(name) 后设置页内容消失（第 \(round) 轮）")
            }
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}

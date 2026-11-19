import XCTest

/// 交互文档 §15 验收场景中可在模拟器自动执行的部分（编号见各测试名）。
/// 每次启动都用新的临时库（`TUNEHAVEN_FRESH_STORE`），曲库干净、互不影响；I-02 同一用例内两次启动共用一个。
final class AcceptanceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    // MARK: - I-01 空曲库首次启动

    @MainActor
    func testI01EmptyLibraryKeepsTabsAndReachesImport() {
        let app = launch(seeded: false)
        for tab in ["音乐库", "歌单", "设置"] {
            expect(app.buttons[tab], timeout: 15, "缺少 Tab：\(tab)")
        }
        expect(app.staticTexts["还没有音乐"], timeout: 5)
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "空曲库启动不应申请权限")

        app.buttons["导入音乐"].firstMatch.tap()
        expect(app.buttons["import.source.files"], timeout: 5)
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "打开导入方式不应申请权限")
        attach(app, name: "I-01-empty-import")
    }

    // MARK: - I-02 冷启动恢复

    @MainActor
    func testI02ColdStartRestoresLastSongPaused() throws {
        // 需要跨启动保留曲库：这次运行专用、按名字复用的临时库
        let store = "coldstart-\(UUID().uuidString)"
        var app = launch(store: store)
        play("交互测试2", in: app)
        if app.buttons["player.playPause"].label == "暂停" { app.buttons["player.playPause"].tap() }
        closePlayer(app)
        let current = miniPlayer(app, title: "交互测试2")
        expect(current, timeout: 5)
        app.terminate()

        // 冷启动：上次歌曲由「继续听」卡承接，开播前不显示迷你播放器
        app = launch(store: store)
        let resume = app.buttons["继续播放：交互测试2"]
        expect(resume, timeout: 15, "未恢复上次歌曲")
        XCTAssertFalse(miniPlayer(app, title: "交互测试2").exists, "开播前不应显示迷你播放器")
        attach(app, name: "I-02-restored")

        // 继续播放：直接开播、留在曲库，卡片收起由迷你播放器接手，暂停后仍保留
        resume.tap()
        expect(miniPlayer(app, title: "交互测试2"), timeout: 5, "开播后应显示迷你播放器")
        XCTAssertFalse(app.buttons["收起播放器"].exists, "继续播放不应展开全屏播放器")
        expect(app.buttons["暂停"], timeout: 5)
        XCTAssertFalse(resume.exists, "开播后继续听卡应收起")
        app.buttons["暂停"].tap()
        expect(app.buttons["播放"], timeout: 3)
        XCTAssertTrue(miniPlayer(app, title: "交互测试2").exists, "暂停后迷你播放器应保留")
        attach(app, name: "I-02-resumed")
    }

    // MARK: - I-03 Tab／详情切换

    @MainActor
    func testI03TabSwitchKeepsDetailAndPlayback() {
        let app = launch()
        play("交互测试1", in: app)
        closePlayer(app)
        expect(app.buttons["暂停"], timeout: 5)

        app.buttons["专辑"].tap()
        let album = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "未知专辑")).firstMatch
        expect(album, timeout: 5)
        album.tap()
        let detailTitle = app.staticTexts["未知专辑"].firstMatch
        expect(detailTitle, timeout: 5)

        app.buttons["歌单"].tap()
        expect(app.staticTexts["我喜欢"].firstMatch, timeout: 5)
        app.buttons["音乐库"].tap()
        expect(detailTitle, timeout: 5, "返回音乐库应保留在专辑详情")
        XCTAssertTrue(miniPlayer(app, title: "交互测试1").exists)
        XCTAssertTrue(app.buttons["暂停"].exists, "切换 Tab 不应影响播放")
        attach(app, name: "I-03-detail-kept")
    }

    // MARK: - I-04 搜索快速连续改词，清除与取消

    @MainActor
    func testI04RapidSearchShowsLatestAndClearDiffersFromCancel() {
        let app = launch()
        let field = app.textFields["搜索歌曲、艺术家、专辑"]
        expect(field, timeout: 20)
        field.tap()
        field.typeText("交互测试1")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        field.typeText("3")

        expect(songRow(app, "交互测试3"), timeout: 5)
        XCTAssertFalse(songRow(app, "交互测试1").exists, "旧查询结果不应残留")

        app.buttons["清除搜索内容"].tap()
        XCTAssertEqual(field.value as? String ?? "", "搜索歌曲、艺术家、专辑")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "清除应保留焦点")

        field.typeText("交互")
        app.buttons["取消"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1), "取消应收起键盘")
        expect(songRow(app, "交互测试4"), timeout: 5, "取消后回到浏览列表")
        attach(app, name: "I-04-after-cancel")
    }

    // MARK: - I-05 无结果与拼音搜索

    @MainActor
    func testI05NoResultsAndPinyinInitials() {
        let app = launch()
        let field = app.textFields["搜索歌曲、艺术家、专辑"]
        expect(field, timeout: 20)
        field.tap()
        field.typeText("zzzq")
        expect(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "没有找到", "相关音乐")).firstMatch, timeout: 5)
        XCTAssertTrue(app.staticTexts["试试拼音首字母"].exists)
        attach(app, name: "I-05-no-results")

        app.buttons["清除搜索内容"].tap()
        field.typeText("jhcs")
        expect(songRow(app, "交互测试1"), timeout: 5, "拼音首字母应匹配")
        attach(app, name: "I-05-pinyin")
    }

    // MARK: - I-06 收藏／删除／撤销

    @MainActor
    func testI06FavoriteSyncsAndDeleteCanBeUndone() {
        let app = launch()
        let row = songRow(app, "交互测试4")
        expect(row, timeout: 20)
        app.buttons["更多操作：交互测试4"].firstMatch.tap()
        app.buttons["喜欢"].tap()
        // 收藏状态在行的容器上（读屏会读到「已喜欢」）
        expect(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "交互测试4", "已喜欢")).firstMatch,
               timeout: 5)

        app.buttons["歌单"].tap()
        let favorites = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "我喜欢")).firstMatch
        expect(favorites, timeout: 5)
        favorites.tap()
        expect(songRow(app, "交互测试4"), timeout: 5, "收藏应同步到我喜欢")

        app.buttons["音乐库"].tap()
        expect(row, timeout: 5)
        app.buttons["更多操作：交互测试4"].firstMatch.tap()
        app.buttons["从音乐库删除"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "删除")).firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        expect(app.buttons["撤销"], timeout: 5)
        // 后台 Tab 的读屏树不会即时刷新，只看当前可点的行
        expectVisible("交互测试4", false, in: app, "删除后音乐库应移除")
        app.buttons["歌单"].tap()
        expect(app.navigationBars["我喜欢"], timeout: 5)
        expectVisible("交互测试4", false, in: app, "删除后我喜欢应同步移除")
        app.buttons["音乐库"].tap()
        app.buttons["撤销"].tap()
        expectVisible("交互测试4", true, in: app, "撤销后应恢复")
        app.buttons["歌单"].tap()
        expectVisible("交互测试4", true, in: app, "撤销后我喜欢应恢复")
        attach(app, name: "I-06-undo")
    }

    // MARK: - I-07 迷你控制与主体点击

    @MainActor
    func testI07MiniPlayButtonDoesNotExpandAndBodyDoesNotRestart() {
        let app = launch()
        play("交互测试1", in: app)
        closePlayer(app)
        let pause = app.buttons["暂停"]
        expect(pause, timeout: 5)

        pause.tap()
        expect(app.buttons["播放"], timeout: 3)
        XCTAssertFalse(app.buttons["收起播放器"].exists, "迷你播放按钮不应展开播放器")

        miniPlayer(app, title: "交互测试1").tap()
        expect(app.buttons["收起播放器"], timeout: 5)
        XCTAssertEqual(app.buttons["player.playPause"].label, "播放", "展开不应重新开始播放")
        attach(app, name: "I-07-expanded-paused")
    }

    // MARK: - I-08 播放模式

    @MainActor
    func testI08PlayModeCyclesThroughFourLabels() {
        let app = launch()
        play("交互测试1", in: app)
        let mode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "播放模式：")).firstMatch
        expect(mode, timeout: 5)
        var labels: [String] = []
        for _ in 0..<5 {
            labels.append(mode.label)
            mode.tap()
        }
        XCTAssertEqual(Set(labels.prefix(4)).count, 4, "应有四种模式：\(labels)")
        XCTAssertEqual(labels[0], labels[4], "第五次应回到起始模式")
    }

    // MARK: - I-13 大字号

    @MainActor
    func testI13LargestTextKeepsControlsReachable() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        expect(songRow(app, "交互测试1"), timeout: 20)
        play("交互测试1", in: app)
        let playPause = app.buttons["player.playPause"]
        for _ in 0..<8 where !playPause.isHittable { app.swipeUp() }
        XCTAssertTrue(playPause.isHittable)
        attach(app, name: "I-13-player-ax5")
        closePlayer(app)
        for tab in ["音乐库", "歌单", "设置"] {
            XCTAssertTrue(app.buttons[tab].isHittable, "最大字号下 Tab 不可点：\(tab)")
        }
        XCTAssertTrue(app.buttons["下一首"].isHittable)
        attach(app, name: "I-13-library-ax5")
    }

    // MARK: - I-19 无障碍审计

    @MainActor
    func testI19AccessibilityAuditOnMainScreens() throws {
        let app = launch()
        expect(songRow(app, "交互测试1"), timeout: 20)
        var issues: [String] = []
        func audit(_ screen: String) throws {
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .trait]) { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) id=\($0.identifier) label=\($0.label) frame=\($0.frame)" } ?? "-"
                issues.append("[\(screen)] \(issue.compactDescription) — \(element)")
                return true
            }
        }
        try audit("音乐库")
        app.buttons["歌单"].tap()
        try audit("歌单")
        app.buttons["设置"].tap()
        try audit("设置")
        app.buttons["音乐库"].tap()
        play("交互测试1", in: app)
        try audit("播放器")
        let report = XCTAttachment(string: issues.joined(separator: "\n"))
        report.name = "I-19-audit"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertTrue(issues.isEmpty, "无障碍审计问题 \(issues.count) 项：\n" + issues.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    @MainActor
    /// `store` 为 nil 时每次启动都是新库；给名字时同名的多次启动共用一个库。
    private func launch(seeded: Bool = true, store: String? = nil, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEHAVEN_FRESH_STORE"] = store ?? "1"
        if seeded { app.launchEnvironment["TUNEHAVEN_SEED_DIR"] = (try? SeedAudio.directory().path) ?? "" }
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    private func songRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        // 行的读屏标签以歌名开头，后接分隔符和艺术家（系统合并时可能用「、」）
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT label BEGINSWITH %@", title, "\(title)0")).firstMatch
    }

    /// 迷你播放器主体合并了子元素，类型不是 Button
    private func miniPlayer(_ app: XCUIApplication, title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "当前歌曲：\(title)")).firstMatch
    }

    @MainActor
    private func play(_ title: String, in app: XCUIApplication) {
        let row = songRow(app, title)
        expect(row, timeout: 20, "找不到歌曲：\(title)")
        row.tap()
        expect(app.buttons["收起播放器"], timeout: 5, "点击歌曲应展开播放器")
    }

    @MainActor
    private func closePlayer(_ app: XCUIApplication) {
        app.buttons["收起播放器"].tap()
        expect(app.buttons["音乐库"], timeout: 5)
    }

    /// 等元素出现；失败时附上当前界面树，便于定位
    @MainActor
    private func expect(_ element: XCUIElement, timeout: TimeInterval, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard !element.waitForExistence(timeout: timeout) else { return }
        let tree = XCTAttachment(string: XCUIApplication().debugDescription)
        tree.name = "tree-\(line)"
        tree.lifetime = .keepAlways
        add(tree)
        XCTFail("未出现：\(element) \(message)", file: file, line: line)
    }

    /// 当前界面上是否有可点的这首歌（排除后台 Tab 里过期的读屏元素）
    @MainActor
    private func expectVisible(_ title: String, _ visible: Bool, in app: XCUIApplication, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title)、"))
        let deadline = Date().addingTimeInterval(5)
        func shown() -> Bool { rows.allElementsBoundByIndex.contains { $0.exists && $0.isHittable } }
        while shown() != visible && Date() < deadline { usleep(200_000) }
        guard shown() != visible else { return }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "tree-\(line)"
        tree.lifetime = .keepAlways
        add(tree)
        XCTFail(message, file: file, line: line)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// 四首 2 分钟静音 WAV，标题为「交互测试1…4」。足够长，测试过程中不会自动切到下一首。
enum SeedAudio {
    static func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("acceptance-seed", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func little(_ n: Int, bytes: Int) -> Data { Data((0..<bytes).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
        let payload = Data(repeating: 0, count: 16000 * 120)
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

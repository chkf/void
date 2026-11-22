import XCTest

extension XCUIApplication {
    func confirmProjectLaunch(file: StaticString = #filePath, line: UInt = #line) {
        let launch = alerts.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "project.launch", "启动")).firstMatch
        XCTAssertTrue(launch.waitForExistence(timeout: 20), debugDescription, file: file, line: line)
        launch.tap()
    }

    var projectSettingsButton: XCUIElement {
        buttons.matching(NSPredicate(format: "identifier == %@ OR (label == %@ AND identifier != %@)",
                                     "project.settings", "设置", "host.settings")).firstMatch
    }

    func returnToProjectList(file: StaticString = #filePath, line: UInt = #line) {
        let manage = buttons["host.manage"].firstMatch
        if !manage.exists {
            let settings = projectSettingsButton
            guard settings.waitForExistence(timeout: 12) else {
                return XCTFail("找不到项目设置\n" + debugDescription, file: file, line: line)
            }
            settings.tap()
        }
        let library = navigationBars["所有项目"]
        for _ in 0..<6 {
            if manage.exists {
                let bounds = manage.frame
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                if !bounds.isEmpty && !bounds.isInfinite && frame.contains(center) {
                    manage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    if library.waitForExistence(timeout: 3) { return }
                }
            }
            // In landscape a swipe starting at the screen edge lands on the native tab bar.
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(library.waitForExistence(timeout: 12), debugDescription, file: file, line: line)
    }

    func revealRecentProject(_ row: XCUIElement) -> Bool {
        // With large Dynamic Type, SwiftUI creates the first project row only after scrolling.
        guard navigationBars["所有项目"].waitForExistence(timeout: 45) else { return false }
        _ = row.waitForExistence(timeout: 5)
        for _ in 0..<8 {
            if row.exists {
                let bounds = row.frame
                if !bounds.isEmpty && frame.contains(CGPoint(x: bounds.midX, y: bounds.midY)) && row.isHittable { return true }
            }
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return false
    }
}

final class HostTests: XCTestCase {
    @MainActor func testFirstPreviewPermissionChoicesAndSQLiteSurviveRelaunch() throws {
        continueAfterFailure = false
        let expected = ProcessInfo.processInfo.environment["VOID_CONSENT_PROJECT"]
        let app = XCUIApplication()
        app.launch()
        if !app.buttons["host.import"].waitForExistence(timeout:4) {
            app.returnToProjectList()
        }
        let candidates = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","project.row.Void Consent "))
        let row = expected.map { app.buttons["project.row." + $0] } ?? candidates.firstMatch
        XCTAssertTrue(app.revealRecentProject(row),app.debugDescription)
        if expected == nil { XCTAssertEqual(candidates.count,1,"需要测试脚本准备的独立项目目录") }
        let fixture = String(row.identifier.dropFirst("project.row.".count))
        row.tap()
        app.confirmProjectLaunch()

        let database = app.alerts["允许「" + fixture + "」使用项目专属数据库？"]
        XCTAssertTrue(database.waitForExistence(timeout:100),app.debugDescription)
        database.buttons["允许"].tap()
        let files = app.alerts["允许「" + fixture + "」读取项目文件？"]
        XCTAssertTrue(files.waitForExistence(timeout:20),app.debugDescription)
        files.buttons["不允许"].tap()
        XCTAssertTrue(app.staticTexts["数据库已打开"].waitForExistence(timeout:25),app.debugDescription)
        XCTAssertTrue(app.staticTexts["PERMISSION_DENIED"].exists)
        app.buttons["写入测试记录"].tap()
        XCTAssertTrue(app.staticTexts["测试记录已保存"].waitForExistence(timeout:15),app.debugDescription)
        let confirmed = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.buttons["scan.cancel"])
        XCTAssertEqual(XCTWaiter.wait(for:[confirmed],timeout:20),.completed)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["已读回测试记录"].waitForExistence(timeout:80),app.debugDescription)
        XCTAssertTrue(app.staticTexts["PERMISSION_DENIED"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testCreateNativeFormAndColdReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let create = app.buttons["host.create"]
        if !create.waitForExistence(timeout: 4) {
            app.returnToProjectList()
        }
        XCTAssertFalse(app.buttons["扫描本机项目"].exists)
        XCTAssertTrue(app.navigationBars["所有项目"].exists)
        XCTAssertFalse(app.buttons["host.github"].exists)
        create.tap()
        app.buttons["host.github"].tap()
        XCTAssertTrue(app.textFields["github.address"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["github.clone"].isEnabled)
        app.navigationBars["从 GitHub 导入"].buttons["BackButton"].tap()
        let cancelCreation = app.navigationBars["创建项目"].buttons["取消"]
        XCTAssertTrue(cancelCreation.waitForExistence(timeout: 8), app.debugDescription)
        cancelCreation.tap()
        app.buttons["host.settings"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))
        let settingsElements = app.descendants(matching: .any)
        XCTAssertTrue(settingsElements.matching(NSPredicate(format: "label BEGINSWITH %@", "版本")).firstMatch.exists)
        for title in ["构建号", "原生控件协议", "SDK 版本", "SDK 能力"] {
            XCTAssertFalse(settingsElements.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists)
        }
        XCTAssertFalse(app.buttons["host.manage"].exists)
        app.buttons["settings.language"].tap()
        app.buttons["language.en"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["All Projects"].waitForExistence(timeout: 12))
        create.tap()
        XCTAssertTrue(app.navigationBars["Create Project"].exists)
        XCTAssertEqual(app.buttons["host.github"].label, "Import from GitHub")
        app.buttons["Cancel"].tap()
        app.buttons["host.settings"].tap()
        app.buttons["settings.language"].tap()
        app.buttons["language.zh-Hans"].tap()
        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 8))
        app.navigationBars["语言"].buttons["BackButton"].tap()
        app.buttons["完成"].tap()
        create.tap()
        let field = app.textFields["project.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "界面")).firstMatch.exists)
        field.tap()
        let name = "Test-" + String(UUID().uuidString.prefix(8))
        field.typeText(name)
        app.buttons["project.createLocal"].tap()
        let created = app.alerts["项目已创建"]
        XCTAssertTrue(created.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(Set(created.buttons.allElementsBoundByIndex.map(\.label)), ["打开 OpenMinis", "完成"])
        created.buttons["打开 OpenMinis"].tap()
        let unavailable = app.alerts["无法打开 OpenMinis"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(unavailable.buttons["前往 App Store"].exists)
        unavailable.buttons["取消"].tap()
        app.terminate()
        app.launch()
        let recent = app.buttons["project.row." + name]
        XCTAssertTrue(app.revealRecentProject(recent))
        recent.tap()
        let launch = app.alerts["启动项目？"]
        XCTAssertTrue(launch.waitForExistence(timeout: 10))
        XCTAssertEqual(Set(launch.buttons.allElementsBoundByIndex.map(\.label)), ["启动", "取消"])
        XCTAssertTrue(launch.staticTexts[name].exists)
        launch.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["所有项目"].exists)
        recent.tap()
        app.confirmProjectLaunch()
        let toggle = app.switches["显示问候"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.projectSettingsButton.exists)
        let input = app.textFields["你的名字"]
        XCTAssertTrue(input.exists)
        XCTAssertTrue(app.staticTexts["你好"].exists)
        let knob = toggle.switches.firstMatch
        let control = knob.exists ? knob.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)) :
            toggle.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5))
        control.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["你好"])
        waitForExpectations(timeout: 8)
        control.tap()
        input.tap()
        input.typeText("Lin")
        XCTAssertTrue(app.staticTexts["你好，Lin"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["scan.cancel"].waitForNonExistence(timeout: 25))
        app.terminate()
        app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.projectSettingsButton.exists)
        XCTAssertFalse(app.buttons["host.manage"].exists)
        app.returnToProjectList()
        XCTAssertTrue(app.revealRecentProject(recent))
        recent.press(forDuration: 1)
        XCTAssertFalse(app.buttons["重命名"].exists)
        app.buttons["详情"].tap()
        XCTAssertTrue(app.navigationBars["项目详情"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format:
            "label CONTAINS %@ OR value == %@", "1.0.0", "1.0.0")).firstMatch.waitForExistence(timeout: 10))
        let nameRow = app.buttons["project.editName"]
        nameRow.tap()
        let alert = app.alerts["修改项目名称"]
        XCTAssertEqual(alert.textFields.firstMatch.value as? String, name)
        alert.buttons["取消"].tap()
        nameRow.tap()
        let edit = alert.textFields.firstMatch
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        edit.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count))
        XCTAssertFalse(alert.buttons["保存"].isEnabled)
        let renamed = "Notes-" + String(UUID().uuidString.prefix(8))
        edit.typeText(renamed)
        alert.buttons["保存"].tap()
        let renamedDetail = app.buttons.matching(NSPredicate(format: "identifier == %@ AND (label CONTAINS %@ OR value == %@)",
            "project.editName", renamed, renamed)).firstMatch
        XCTAssertTrue(renamedDetail.waitForExistence(timeout: 12), app.debugDescription)
        app.buttons["完成"].tap()
        let row = app.buttons["project.row." + renamed]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(recent.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.revealRecentProject(row))
        row.tap()
        XCTAssertTrue(launch.waitForExistence(timeout: 10))
        XCTAssertTrue(launch.staticTexts[renamed].exists)
        launch.buttons["取消"].tap()
        row.swipeLeft()
        let remove = app.buttons["project.row.remove"]
        if remove.exists { remove.tap() }
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: row)
        waitForExpectations(timeout: 8)
        app.terminate()
        app.launch()
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        XCTAssertFalse(row.exists)
    }
}

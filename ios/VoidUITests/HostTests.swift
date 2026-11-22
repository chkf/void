import XCTest

extension XCUIApplication {
    var projectSettingsButton: XCUIElement {
        buttons.matching(NSPredicate(format: "identifier == %@ OR (label == %@ AND identifier != %@)",
                                     "project.settings", "设置", "host.settings")).firstMatch
    }

    func returnToProjectList(file: StaticString = #filePath, line: UInt = #line) {
        let manage = buttons["host.manage"].firstMatch
        if !manage.exists || !manage.isHittable {
            let settings = projectSettingsButton
            guard settings.waitForExistence(timeout: 12) else {
                return XCTFail("找不到项目设置\n" + debugDescription, file: file, line: line)
            }
            settings.tap()
            for _ in 0..<6 {
                if manage.exists && manage.isHittable { break }
                // In landscape a swipe starting at the screen edge lands on the native tab bar.
                let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
                let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        guard manage.exists && manage.isHittable else {
            return XCTFail("设置中找不到项目管理\n" + debugDescription, file: file, line: line)
        }
        manage.tap()
        XCTAssertTrue(navigationBars["所有项目"].waitForExistence(timeout: 12), debugDescription, file: file, line: line)
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
        let preview = app.buttons["project.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15), app.debugDescription)
        preview.tap()

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
        app.buttons["host.github"].tap()
        XCTAssertTrue(app.textFields["github.address"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["github.clone"].isEnabled)
        app.buttons["取消"].tap()
        app.buttons["host.settings"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))
        let settingsElements = app.descendants(matching: .any)
        XCTAssertTrue(settingsElements.matching(NSPredicate(format: "label BEGINSWITH %@", "版本")).firstMatch.exists)
        for title in ["构建号", "原生控件协议", "SDK 版本", "SDK 能力"] {
            XCTAssertFalse(settingsElements.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists)
        }
        XCTAssertFalse(app.buttons["host.manage"].exists)
        app.buttons["完成"].tap()
        create.tap()
        let field = app.textFields["project.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "界面")).firstMatch.exists)
        field.tap()
        let name = "Test-" + String(UUID().uuidString.prefix(8))
        field.typeText(name)
        app.buttons["project.createLocal"].tap()
        let preview = app.buttons["project.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "app/src/main.tsx")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["项目未能打开"].exists)
        let bar = app.navigationBars[name]
        XCTAssertTrue(bar.buttons["project.settings"].isHittable)
        XCTAssertFalse(app.buttons["host.manage"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        let back = bar.buttons.matching(NSPredicate(format: "identifier != %@", "project.settings")).firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        let recent = app.buttons["project.row." + name]
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        recent.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
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
        app.buttons["详情"].tap()
        XCTAssertTrue(app.navigationBars["项目详情"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format:
            "label CONTAINS %@ OR value == %@", "1.0.0", "1.0.0")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["完成"].tap()
        recent.press(forDuration: 1)
        app.buttons["重命名"].tap()
        let alert = app.alerts["重命名项目"]
        XCTAssertEqual(alert.textFields.firstMatch.value as? String, name)
        alert.buttons["取消"].tap()
        XCTAssertTrue(recent.exists)
        recent.press(forDuration: 1)
        app.buttons["重命名"].tap()
        let edit = alert.textFields.firstMatch
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        edit.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count))
        XCTAssertFalse(alert.buttons["保存"].isEnabled)
        let renamed = "Notes-" + String(UUID().uuidString.prefix(8))
        edit.typeText(renamed)
        alert.buttons["保存"].tap()
        let row = app.buttons["project.row." + renamed]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(recent.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.revealRecentProject(row))
        row.tap()
        XCTAssertTrue(app.navigationBars[renamed].waitForExistence(timeout: 10))
        app.returnToProjectList()
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

import XCTest

final class HostTests: XCTestCase {
    func testFirstPreviewPermissionChoicesAndSQLiteSurviveRelaunch() throws {
        continueAfterFailure = false
        let expected = ProcessInfo.processInfo.environment["VOID_CONSENT_PROJECT"]
        let app = XCUIApplication()
        app.launch()
        if !app.buttons["host.local"].waitForExistence(timeout:4) {
            app.buttons["host.manage"].tap()
            app.buttons["host.switch"].tap()
        }
        app.buttons["host.local"].tap()
        let candidates = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","recent.Void Consent "))
        let row = expected.map { app.buttons["recent." + $0] } ?? candidates.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:45),app.debugDescription)
        if expected == nil { XCTAssertEqual(candidates.count,1,"需要测试脚本准备的独立项目目录") }
        let fixture = String(row.identifier.dropFirst("recent.".count))
        row.tap()
        app.buttons["project.preview"].tap()

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
            app.buttons["host.manage"].tap()
            app.buttons["host.switch"].tap()
        }
        create.tap()
        let field = app.textFields["project.name"]
        field.tap()
        let name = "Test-" + String(UUID().uuidString.prefix(8))
        field.typeText(name)
        app.buttons["project.createLocal"].tap()
        let preview = app.buttons["project.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.staticTexts["项目未能打开"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        preview.tap()
        let toggle = app.switches["显示问候"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.firstMatch.exists)
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
        app.terminate()
        app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.navigationBars[name].exists)
        app.buttons["host.manage"].tap()
        XCTAssertTrue(app.buttons["host.switch"].exists)
        XCTAssertTrue(app.buttons["host.reconnect"].exists)
        app.buttons["host.switch"].tap()
        let row = app.buttons["recent." + name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.swipeLeft()
        let remove = app.buttons["recent.remove"]
        if remove.exists { remove.tap() }
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: row)
        waitForExpectations(timeout: 8)
        app.terminate()
        app.launch()
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        XCTAssertFalse(row.exists)
    }
}

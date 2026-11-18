import XCTest

final class HostTests: XCTestCase {
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

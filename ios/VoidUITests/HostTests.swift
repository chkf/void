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
        let toggle = app.switches["显示问候"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let input = app.textFields["你的名字"]
        XCTAssertTrue(input.exists)
        XCTAssertTrue(app.staticTexts["你好"].exists)
        let control = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
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
        XCTAssertTrue(app.buttons["重新授权文件夹"].exists)
    }
}

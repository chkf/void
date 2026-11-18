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
        field.typeText("Test-" + String(UUID().uuidString.prefix(8)))
        app.buttons["project.createLocal"].tap()
        let toggle = app.switches["显示问候"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.textFields["你的名字"].exists)
        XCTAssertTrue(app.staticTexts["你好"].exists)
        toggle.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["你好"])
        waitForExpectations(timeout: 8)
        app.terminate()
        app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 90), app.debugDescription)
        app.buttons["host.manage"].tap()
        XCTAssertTrue(app.buttons["host.switch"].exists)
        XCTAssertTrue(app.buttons["重新授权文件夹"].exists)
    }
}

import UIKit
import XCTest

@MainActor final class LegacySafeAreaScreen: XCTestCase {
    func testDarkScreenOnTheOlderHost() throws {
        continueAfterFailure = false
        let name = try XCTUnwrap(ProcessInfo.processInfo.environment["VOID_NATIVE_UI_PROJECT"])
        let app = XCUIApplication()
        app.launch()
        app.buttons["host.local"].tap()
        let row = app.buttons["recent." + name]
        XCTAssertTrue(app.revealScannedProject(row), app.debugDescription)
        row.tap()
        app.buttons["project.preview"].tap()
        XCTAssertTrue(app.staticTexts["Sample screen"].waitForExistence(timeout: 100))
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["scan.cancel"])
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 30), .completed)
        let photo = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        photo.name = "Old-Dark-Stable"
        photo.lifetime = .keepAlways
        add(photo)
    }
}

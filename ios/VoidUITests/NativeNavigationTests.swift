import XCTest

final class NativeNavigationTests: XCTestCase {
    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
    private func becomes(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 12) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: timeout) == .completed
    }

    func testNativeTabsPreserveDraftScrollThemeAndHostAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }
        app.launch()
        if !app.buttons["host.local"].waitForExistence(timeout: 4) {
            app.buttons["host.manage"].tap()
            app.buttons["host.switch"].tap()
        }
        app.buttons["host.local"].tap()
        let expected = ProcessInfo.processInfo.environment["VOID_NATIVE_UI_PROJECT"]
        let row = expected.map { app.buttons["recent." + $0] } ??
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recent.Void Native UI ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 45), app.debugDescription)
        row.tap()
        app.buttons["project.preview"].tap()

        let components = app.buttons["组件"], appearance = app.buttons["外观"], rows = app.buttons["列表"]
        let manage = app.buttons["host.manage"]
        XCTAssertTrue(components.waitForExistence(timeout: 100), app.debugDescription)
        XCTAssertTrue(becomes(components, "selected == true"))
        XCTAssertTrue(becomes(app.buttons["scan.cancel"], "exists == false", timeout: 30))
        XCTAssertTrue(manage.isHittable)
        let reset = app.buttons["复位"], plus = app.buttons["增加"]
        XCTAssertFalse(reset.isEnabled)
        XCTAssertGreaterThanOrEqual(plus.frame.height, 44)
        XCTAssertGreaterThanOrEqual(manage.frame.height, 44)
        plus.tap()
        XCTAssertTrue(app.staticTexts["1 / 4"].waitForExistence(timeout: 8))
        let input = app.textFields["临时文本"]
        input.tap()
        input.typeText("abc")
        XCTAssertTrue(manage.isHittable)
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            attach(app, "Keyboard")
            input.typeText("\n")
        }
        appearance.tap()
        XCTAssertFalse(input.exists)
        app.buttons["浅色"].tap()
        XCTAssertTrue(app.staticTexts["模式 light"].waitForExistence(timeout: 8))
        components.tap()
        XCTAssertEqual(input.value as? String, "abc")
        XCTAssertTrue(app.staticTexts["1 / 4"].exists)
        attach(app, "Light-Portrait")
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription])
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp()
        let visible = (8...36).map { app.staticTexts["滚动行 \($0)"] }.last(where: { $0.isHittable })
        let anchor = try XCTUnwrap(visible)
        let y = anchor.frame.midY
        XCTAssertTrue(appearance.isHittable)
        appearance.tap()
        app.buttons["深色"].tap()
        XCTAssertTrue(app.staticTexts["模式 dark"].waitForExistence(timeout: 8))
        let third = app.switches["第三个标签"].firstMatch
        third.tap()
        XCTAssertTrue(rows.waitForExistence(timeout: 8))
        rows.tap()
        XCTAssertTrue(app.staticTexts["列表行 1"].waitForExistence(timeout: 8))
        components.tap()
        XCTAssertTrue(anchor.isHittable)
        XCTAssertEqual(anchor.frame.midY, y, accuracy: 3)
        appearance.tap()
        third.tap()
        XCTAssertTrue(becomes(rows, "exists == false"))
        attach(app, "Dark-Portrait")
        device.orientation = .landscapeLeft
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        attach(app, "Dark-Landscape")
        manage.tap()
        XCTAssertTrue(app.buttons["host.switch"].isHittable)
        XCTAssertTrue(app.buttons["host.rescan"].exists)
        XCTAssertTrue(app.buttons["恢复上一可运行版本"].exists)
        app.buttons["完成"].tap()

        device.orientation = .portrait
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(components.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(manage.isHittable)
        attach(app, "Accessibility-XXXL")
        XCTAssertTrue(appearance.isHittable)
    }
}

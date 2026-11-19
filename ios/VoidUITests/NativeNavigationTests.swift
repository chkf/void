import XCTest
import UIKit

final class NativeNavigationTests: XCTestCase {
    @MainActor private func attach(_ name: String) {
        // A window-relative snapshot can crop the rotated app in display coordinates.
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
    private func becomes(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 12) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: timeout) == .completed
    }

    private func brightness(_ app: XCUIApplication) throws -> Double {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / 765
    }

    @MainActor private func audit(_ app: XCUIApplication) throws -> [String] {
        var findings = [String]()
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription]) { issue in
            findings.append("\(issue.element?.label ?? "") · \(issue.detailedDescription)")
            return true
        }
        return findings
    }

    @MainActor func testNativeTabsPreserveDraftScrollThemeAndHostAccess() throws {
        continueAfterFailure = false
        executionTimeAllowance = 360
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
        XCTAssertTrue(app.revealScannedProject(row), app.debugDescription)
        row.tap()
        let preview = app.buttons["project.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15), app.debugDescription)
        preview.tap()

        // iPadOS exposes a floating tab cell and its nested button with the same title.
        let components = app.buttons["组件"].firstMatch, appearance = app.buttons["外观"].firstMatch, rows = app.buttons["列表"].firstMatch
        let manage = app.buttons["host.manage"]
        XCTAssertTrue(components.waitForExistence(timeout: 100), app.debugDescription)
        // iPadOS exposes its top tab as a button without XCTest's phone-only
        // selected trait. Verify the presented page as well as the native
        // controller selection exercised by NativeTabEventTests.
        XCTAssertTrue(app.textFields["临时文本"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["浅色"].exists)
        if UIDevice.current.userInterfaceIdiom == .phone { XCTAssertTrue(becomes(components, "selected == true")) }
        XCTAssertTrue(becomes(app.buttons["scan.cancel"], "exists == false", timeout: 30))
        XCTAssertTrue(manage.isHittable)
        XCTAssertLessThan(manage.frame.midY, app.frame.midY)
        if app.buttons["folder.clear"].exists { XCTAssertLessThan(app.buttons["folder.clear"].frame.midY, app.frame.midY) }
        if UIDevice.current.userInterfaceIdiom == .phone { XCTAssertGreaterThan(components.frame.midY, app.frame.midY) }
        let reset = app.buttons["复位"], plus = app.buttons["增加"]
        let heading = app.staticTexts["原生控件"]
        let standardHeight = heading.frame.height
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
            attach("Keyboard")
            input.typeText("\n")
        }
        appearance.tap()
        XCTAssertFalse(input.exists)
        app.buttons["浅色"].tap()
        XCTAssertTrue(app.staticTexts["模式 light"].waitForExistence(timeout: 8))
        let light = try brightness(app)
        components.tap()
        XCTAssertEqual(input.value as? String, "abc")
        XCTAssertTrue(app.staticTexts["1 / 4"].exists)
        attach("Light-Portrait")
        var findings = try audit(app)
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp()
        let visible = (8...36).map { app.staticTexts["滚动行 \($0)"] }.last(where: { $0.isHittable })
        let anchor = try XCTUnwrap(visible)
        let y = anchor.frame.midY
        XCTAssertTrue(appearance.isHittable)
        appearance.tap()
        app.buttons["深色"].tap()
        XCTAssertTrue(app.staticTexts["模式 dark"].waitForExistence(timeout: 8))
        XCTAssertGreaterThan(light - (try brightness(app)), 0.3)
        let third = app.switches["第三个标签"].firstMatch
        func toggleThird() {
            let knob = third.switches.firstMatch
            let target = knob.exists ? knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)) :
                third.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
            target.tap()
        }
        toggleThird()
        XCTAssertTrue(rows.waitForExistence(timeout: 8))
        rows.tap()
        let firstRow = app.staticTexts["列表行 1"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))
        let firstRowY = firstRow.frame.midY
        app.swipeUp()
        XCTAssertTrue(!firstRow.isHittable || firstRow.frame.midY < firstRowY - 8)
        XCTAssertTrue(components.isHittable)
        attach("Three-Tabs-Scrolled")
        components.tap()
        XCTAssertTrue(anchor.isHittable)
        XCTAssertEqual(anchor.frame.midY, y, accuracy: 3)
        appearance.tap()
        toggleThird()
        XCTAssertTrue(becomes(rows, "exists == false"))
        attach("Dark-Portrait")
        findings += try audit(app)
        device.orientation = .landscapeLeft
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        attach("Dark-Landscape")
        manage.tap()
        XCTAssertTrue(app.buttons["host.switch"].isHittable)
        let recovery = app.buttons["host.recovery"]
        XCTAssertTrue(recovery.isHittable)
        recovery.tap()
        let restore = app.buttons["host.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 8))
        XCTAssertTrue(restore.isHittable)
        attach("Host-Recovery-Landscape")
        app.buttons["host.recoveryDone"].tap()

        device.orientation = .portrait
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(components.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(manage.isHittable)
        XCTAssertTrue(heading.waitForExistence(timeout: 12))
        XCTAssertGreaterThan(heading.frame.height, standardHeight * 1.3)
        attach("Accessibility-XXXL")
        XCTAssertTrue(appearance.isHittable)
        XCTAssertTrue(findings.isEmpty, findings.joined(separator: "\n"))
    }
}

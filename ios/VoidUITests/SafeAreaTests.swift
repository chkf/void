import UIKit
import XCTest

@MainActor
final class SafeAreaTests: XCTestCase {
    private let dark = [32, 72, 88], light = [200, 232, 224]

    private func systemAppearance(_ mode: String) async throws {
        let temporary = FileManager.default.temporaryDirectory
        let request = UUID().uuidString + " " + mode
        let applied = temporary.appendingPathComponent("void-test-appearance-applied")
        try Data(request.utf8).write(to: temporary.appendingPathComponent("void-test-appearance"), options: .atomic)
        let deadline = ContinuousClock.now + .seconds(90)
        while (try? String(contentsOf: applied, encoding: .utf8)) != request {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "Simulator did not apply " + mode, code: 1) }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    private func open(_ app: XCUIApplication) throws {
        app.launchArguments = ["-void.openProjectListOnLaunch", "YES"]
        app.launch()
        app.buttons["host.local"].tap()
        let name = try XCTUnwrap(ProcessInfo.processInfo.environment["VOID_SAFE_AREA_PROJECT"])
        let row = app.buttons["recent." + name]
        guard app.revealScannedProject(row) else { throw NSError(domain: "Missing fixture " + name, code: 1) }
        row.tap()
        app.buttons["project.preview"].tap()
        XCTAssertTrue(app.staticTexts["Sample screen"].waitForExistence(timeout: 100), app.debugDescription)
    }

    @discardableResult
    private func display(_ name: String) -> XCUIScreenshot {
        let display = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: display)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return display
    }

    private func capture(_ name: String, _ app: XCUIApplication, above title: String, rgb: [Int],
                         file: StaticString = #filePath, line: UInt = #line) throws {
        let heading = app.staticTexts[title].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 12), file: file, line: line)
        let frame = heading.frame
        let screenshot = display(name)
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        func check(_ x: CGFloat, from y: CGFloat, to end: CGFloat) throws {
            let rect = CGRect(x: floor(x * scale), y: floor(y * scale), width: 1,
                              height: max(1, ceil(end * scale) - floor(y * scale)))
            let column = try XCTUnwrap(image.cropping(to: rect))
            var pixels = [UInt8](repeating: 0, count: 4 * column.height)
            try pixels.withUnsafeMutableBytes { bytes in
                let ctx = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: column.height,
                    bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                ctx.draw(column, in: CGRect(x: 0, y: 0, width: 1, height: column.height))
            }
            if let i = stride(from: 0, to: pixels.count, by: 4).first(where: { offset in
                rgb.indices.contains { abs(Int(pixels[offset + $0]) - rgb[$0]) > 8 }
            }) {
                XCTFail("\(name) x=\(x) y=\(y)...\(end)pt RGB \(Array(pixels[i..<i+3])), expected \(rgb)", file: file, line: line)
            }
        }
        for fraction in [0.24, 0.76] {
            try check(app.frame.minX + app.frame.width * fraction, from: app.frame.minY + 7, to: app.frame.minY + 9)
        }
        // Inside the rounded screen edge but outside the title, feedback and system glyphs.
        if UIDevice.current.userInterfaceIdiom == .phone && app.frame.height > app.frame.width {
            try check(app.frame.minX + 8, from: app.frame.minY + 43, to: frame.minY + 3)
        }
    }

    func testDarkBackgroundWhileHostDisplaysRecoveryFeedback() async throws {
        executionTimeAllowance = 360
        let device = XCUIDevice.shared, app = XCUIApplication()
        device.orientation = .portrait
        try await systemAppearance("dark")
        try open(app)
        try capture("Dark-Opened", app, above: "Sample screen", rgb: dark)
        let expanded = app.staticTexts["Sample screen"].firstMatch.frame
        let input = app.textFields["Draft"]
        input.tap()
        input.typeText("saved")
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            try capture("Dark-Keyboard", app, above: "Sample screen", rgb: dark)
            input.typeText("\n")
        }
        app.scrollViews.firstMatch.swipeUp()
        display("Dark-Scrolled")
        if UIDevice.current.userInterfaceIdiom == .phone {
            let inline = app.navigationBars["Sample screen"].staticTexts["Sample screen"].firstMatch
            XCTAssertTrue(inline.waitForExistence(timeout: 12))
            XCTAssertEqual(inline.frame.midX, app.frame.midX, accuracy: 10)
            XCTAssertLessThan(inline.frame.height, expanded.height)
        }
        app.buttons["Settings"].firstMatch.tap()
        try capture("Dark-SecondTab", app, above: "Appearance", rgb: dark)
        app.buttons["Scroll title"].tap()
        app.buttons["Sample"].firstMatch.tap()
        app.scrollViews.firstMatch.swipeDown()
        try capture("Dark-ScrollHeading", app, above: "Scroll heading", rgb: dark)
        let finger = app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        finger.press(forDuration: 0.08, thenDragTo: finger.withOffset(CGVector(dx: 0, dy: -32)),
                     withVelocity: .slow, thenHoldForDuration: 0.7)
        display("Scroll-Heading-Passing-Status")
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Scroll title"].tap()
        app.buttons["host.manage"].tap()
        app.buttons["host.recovery"].tap()
        app.buttons["host.restore"].tap()
        XCTAssertTrue(app.staticTexts["preview.error"].waitForExistence(timeout: 60))
        try capture("Dark-RecoveryFeedback", app, above: "Appearance", rgb: dark)
        app.buttons["Change palette"].tap()
        try capture("Alternate-RecoveryFeedback", app, above: "Appearance", rgb: [72, 45, 84])
        app.buttons["Light"].tap()
        try capture("Light-RecoveryFeedback", app, above: "Appearance", rgb: [255, 228, 184])
        app.buttons["Sample"].firstMatch.tap()
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertEqual(input.value as? String, "saved")
        device.press(.home)
        app.activate()
        try capture("Foreground", app, above: "Sample screen", rgb: [255, 228, 184])
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["host.manage"].firstMatch.tap()
        app.buttons["host.switch"].tap()
        XCTAssertTrue(app.buttons["host.local"].waitForExistence(timeout: 12))
    }

    func testLightSystemChangesAndScreenWithoutTabsOrTheme() async throws {
        executionTimeAllowance = 300
        let device = XCUIDevice.shared, app = XCUIApplication()
        device.orientation = .portrait
        try await systemAppearance("light")
        try open(app)
        try capture("Light-Opened", app, above: "Sample screen", rgb: light)
        try await systemAppearance("dark")
        try capture("System-Dark", app, above: "Sample screen", rgb: dark)
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Dark"].tap()
        try await systemAppearance("light")
        try capture("Forced-Dark", app, above: "Appearance", rgb: dark)
        app.buttons["Toggle tabs"].tap()
        XCTAssertTrue(app.buttons["Sample"].firstMatch.waitForNonExistence(timeout: 12))
        try capture("Dark-NoTabs", app, above: "Appearance", rgb: dark)
        app.buttons["Toggle theme"].tap()
        try capture("System-NoTheme-NoTabs", app, above: "Appearance", rgb: [255, 255, 255])
        app.buttons["Toggle tabs"].tap()
        try capture("System-NoTheme-Tabs", app, above: "Appearance", rgb: [255, 255, 255])
        app.buttons["host.manage"].tap()
        app.buttons["host.switch"].tap()
    }
}

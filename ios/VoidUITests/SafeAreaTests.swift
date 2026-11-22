import UIKit
import XCTest

@MainActor
final class SafeAreaTests: XCTestCase {
    private let dark = [32, 72, 88], light = [200, 232, 224]

    private func simulatorAction(_ action: String) async throws {
        let temporary = FileManager.default.temporaryDirectory
        let request = UUID().uuidString + " " + action
        let applied = temporary.appendingPathComponent("void-test-action-applied")
        try Data(request.utf8).write(to: temporary.appendingPathComponent("void-test-action"), options: .atomic)
        let deadline = ContinuousClock.now + .seconds(90)
        while (try? String(contentsOf: applied, encoding: .utf8)) != request {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "Simulator did not apply " + action, code: 1) }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    private func open(_ app: XCUIApplication, darkMode: Bool) throws {
        app.launchArguments = ["-void.openProjectListOnLaunch", "YES"]
        app.launch()
        let name = try XCTUnwrap(ProcessInfo.processInfo.environment["VOID_SAFE_AREA_PROJECT"])
        let row = app.buttons["project.row." + name]
        XCTAssertTrue(app.buttons["host.import"].waitForExistence(timeout: 12), app.debugDescription)
        try checkLibraryActions(app, darkMode: darkMode)
        guard app.revealRecentProject(row) else { throw NSError(domain: "Missing fixture " + name, code: 1) }
        row.tap()
        XCTAssertTrue(app.navigationBars[name].exists, app.debugDescription)
        app.buttons["project.preview"].tap()
        XCTAssertTrue(app.staticTexts["Sample screen"].waitForExistence(timeout: 100), app.debugDescription)
    }

    private func checkLibraryActions(_ app: XCUIApplication, darkMode: Bool) throws {
        let displayImage = display(darkMode ? "Library-Dark" : "Library-Light")
        let image = try XCTUnwrap(displayImage.image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let area = app.buttons["host.create"].frame.union(app.buttons["host.import"].frame)
        let rows = try XCTUnwrap(image.cropping(to: area.applying(CGAffineTransform(scaleX: scale, y: scale))))
        let strideBytes = rows.width * 4
        var pixels = [UInt8](repeating: 0, count: strideBytes * rows.height)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: rows.width, height: rows.height,
                bitsPerComponent: 8, bytesPerRow: strideBytes, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(rows, in: CGRect(x: 0, y: 0, width: CGFloat(rows.width), height: CGFloat(rows.height)))
        }
        var ink = 0, blue = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            if darkMode ? min(r, g, b) > 220 : max(r, g, b) < 40 { ink += 1 }
            if b - r > 64 && b - g > 24 { blue += 1 }
        }
        XCTAssertGreaterThan(ink, 100)
        XCTAssertLessThan(blue, 20)
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
        try await simulatorAction("dark")
        try open(app, darkMode: true)
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
        try await simulatorAction("add-source-error")
        addTeardownBlock { @MainActor in try await self.simulatorAction("clear-source-error") }
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
        app.buttons["预览选项"].tap()
        XCTAssertTrue(app.buttons["收起提示"].exists)
        app.buttons["返回项目列表"].tap()
        XCTAssertTrue(app.buttons["host.import"].waitForExistence(timeout: 12))
    }

    func testLightSystemChangesAndScreenWithoutTabsOrTheme() async throws {
        executionTimeAllowance = 300
        let device = XCUIDevice.shared, app = XCUIApplication()
        device.orientation = .portrait
        try await simulatorAction("light")
        try open(app, darkMode: false)
        try capture("Light-Opened", app, above: "Sample screen", rgb: light)
        try await simulatorAction("dark")
        try capture("System-Dark", app, above: "Sample screen", rgb: dark)
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Dark"].tap()
        try await simulatorAction("light")
        try capture("Forced-Dark", app, above: "Appearance", rgb: dark)
        app.buttons["Toggle tabs"].tap()
        XCTAssertTrue(app.buttons["Sample"].firstMatch.waitForNonExistence(timeout: 12))
        try capture("Dark-NoTabs", app, above: "Appearance", rgb: dark)
        app.buttons["Toggle theme"].tap()
        try capture("System-NoTheme-NoTabs", app, above: "Appearance", rgb: [255, 255, 255])
        app.buttons["Toggle tabs"].tap()
        try capture("System-NoTheme-Tabs", app, above: "Appearance", rgb: [255, 255, 255])
        app.buttons["host.manage"].tap()
        XCTAssertTrue(app.navigationBars["所有项目"].waitForExistence(timeout: 12))
    }
}

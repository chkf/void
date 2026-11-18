import XCTest

final class FolderPickerTests: XCTestCase {
    private let app = XCUIApplication()
    private let token = UUID().uuidString
    private var fixture: String { "Void Picker " + String(token.prefix(8)) }

    private func named(_ labels: [String], in elements: XCUIElementQuery) -> XCUIElement {
        elements.matching(NSPredicate(format:"label IN %@ OR identifier IN %@",labels,labels)).firstMatch
    }
    private var navigation: XCUIElement { app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].firstMatch }
    private var openButton: XCUIElement { app.buttons["DOCPicker.actionButton"].firstMatch }
    private func showBrowser() {
        if !openButton.waitForExistence(timeout:8) || !openButton.isEnabled {
            let browse = named(["Browse","浏览"],in:app.tabBars.buttons)
            if browse.exists && browse.isHittable { browse.tap() }
        }
        XCTAssertTrue(openButton.waitForExistence(timeout:60),app.debugDescription)
    }
    private func selectDirectory() {
        showBrowser()
        // This is Apple's Open action on the displayed directory. Assert the returned
        // project's unique name after dismissal instead of interpreting Files' virtual cells.
        XCTAssertTrue(openButton.isEnabled,app.debugDescription)
        openButton.tap()
        if app.alerts.firstMatch.waitForExistence(timeout:2) {
            let allow = named(["Allow","允许","Open","打开"],in:app.alerts.buttons)
            if allow.exists { allow.tap() }
        } else if openButton.exists {
            let alert = XCUIApplication(bundleIdentifier:"com.apple.springboard").alerts
            let allow = named(["Allow","允许"],in:alert.buttons)
            if allow.exists { allow.tap() }
        }
        awaitDismissal()
    }
    private func awaitDismissal() {
        let gone = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:openButton)
        XCTAssertEqual(XCTWaiter.wait(for:[gone],timeout:15),.completed,app.debugDescription)
    }
    private func cancelPicker() {
        showBrowser()
        let cancel = named(["Cancel","取消","Close","关闭"],in:navigation.buttons)
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else {
            // Compact Files exposes Open and the history controls. Drag its actual sheet handle.
            let handle = named(["Sheet Grabber","表单抓取按钮"],in:app.buttons)
            let top = handle.exists ? handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)) :
                navigation.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0))
            let bottom = app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.9))
            top.press(forDuration:0.12,thenDragTo:bottom)
        }
        awaitDismissal()
        let done = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","已取消目录操作"),object:app.staticTexts["folder.status"])
        XCTAssertEqual(XCTWaiter.wait(for:[done],timeout:12),.completed,app.debugDescription)
        app.buttons["folder.clear"].tap()
    }

    private func openLibrary() {
        continueAfterFailure = false
        executionTimeAllowance = 360
        app.launchEnvironment["VOID_PICKER_TEST_PROJECT"] = token
        app.launch()
        if !app.buttons["host.import"].waitForExistence(timeout:3) {
            app.buttons["host.manage"].tap(); app.buttons["host.switch"].tap()
        }
        XCTAssertFalse(app.buttons["recent." + fixture].exists)
    }
    private func importAndPreview() {
        app.buttons["host.import"].tap(); selectDirectory()
        let status = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","已找到「" + fixture + "」"),object:app.staticTexts["folder.status"])
        XCTAssertEqual(XCTWaiter.wait(for:[status],timeout:25),.completed,app.debugDescription)
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:70),app.debugDescription)
    }
    private func reconnect() {
        app.buttons["host.manage"].tap(); app.buttons["host.reconnect"].tap()
    }

    func testSystemOpenImportsPreviewsAndReconnectsOriginal() {
        openLibrary()
        importAndPreview()
        reconnect(); selectDirectory()
        expectation(for:NSPredicate(format:"label == %@", "已核验原项目目录"),evaluatedWith:app.staticTexts["folder.status"])
        waitForExpectations(timeout:25)
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:30),app.debugDescription)
    }

    func testSystemDismissalAndInterruptionKeepPreviousProject() {
        openLibrary()
        app.buttons["host.import"].tap(); cancelPicker()
        importAndPreview()
        reconnect(); cancelPicker()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.exists,app.debugDescription)
        reconnect()
        showBrowser()
        app.terminate(); app.launch()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:60),app.debugDescription)
    }
}

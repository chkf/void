import XCTest

final class FolderPickerTests: XCTestCase {
    private let app = XCUIApplication()
    private let fixture = "Void Picker Test"

    private func named(_ labels: [String], in elements: XCUIElementQuery) -> XCUIElement {
        elements.matching(NSPredicate(format:"label IN %@ OR identifier IN %@",labels,labels)).firstMatch
    }
    private var browser: XCUIElement { app.otherElements["Browse View (Picker)"].firstMatch }
    private var openButton: XCUIElement { app.buttons["DOCPicker.actionButton"].firstMatch }
    private func folder(_ title: String) -> XCUIElement {
        app.collectionViews["File View"].cells.matching(NSPredicate(format:"label == %@ OR label BEGINSWITH %@",title,title + ",")).firstMatch
    }
    private func selectDirectory() {
        XCTAssertTrue(browser.waitForExistence(timeout:20),app.debugDescription)
        let alreadyInside = browser.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH 'DOC.browsingRoot' AND identifier ENDSWITH %@",fixture)).firstMatch
        if !alreadyInside.exists {
            let project = folder(fixture)
            if !project.waitForExistence(timeout:2) {
                let container = folder("void")
                if !container.waitForExistence(timeout:2) {
                    let browse = named(["Browse","浏览"],in:browser.buttons)
                    if browse.exists { browse.tap() }
                    let local = named(["On My iPhone","我的 iPhone","在我的 iPhone 上"],in:browser.descendants(matching:.any))
                    if local.waitForExistence(timeout:5) { local.tap() }
                }
                if container.waitForExistence(timeout:5) { container.tap() }
            }
            XCTAssertTrue(project.waitForExistence(timeout:12),app.debugDescription)
            project.tap()
        }
        XCTAssertTrue(openButton.waitForExistence(timeout:10),app.debugDescription)
        openButton.tap()
        let allow = named(["Allow","允许"],in:app.buttons)
        if allow.waitForExistence(timeout:2) { allow.tap() }
        else if browser.exists {
            let alert = XCUIApplication(bundleIdentifier:"com.apple.springboard").alerts
            let systemAllow = named(["Allow","允许"],in:alert.buttons)
            if systemAllow.exists { systemAllow.tap() }
        }
        awaitDismissal()
    }
    private func awaitDismissal() {
        let gone = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:browser)
        XCTAssertEqual(XCTWaiter.wait(for:[gone],timeout:15),.completed,app.debugDescription)
    }
    private func cancelPicker() {
        XCTAssertTrue(browser.waitForExistence(timeout:20),app.debugDescription)
        let cancel = named(["Cancel","取消","Close","关闭"],in:browser.buttons)
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else {
            // Compact Files exposes Open and the history controls. Drag its actual sheet handle.
            let top = browser.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.014))
            let bottom = browser.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.9))
            top.press(forDuration:0.12,thenDragTo:bottom)
        }
        awaitDismissal()
        let done = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","已取消目录操作"),object:app.staticTexts["folder.status"])
        XCTAssertEqual(XCTWaiter.wait(for:[done],timeout:12),.completed,app.debugDescription)
        app.buttons["folder.clear"].tap()
    }

    private func openLibrary() {
        continueAfterFailure = false
        app.launch()
        if !app.buttons["host.import"].waitForExistence(timeout:3) {
            app.buttons["host.manage"].tap(); app.buttons["host.switch"].tap()
        }
    }
    private func importAndPreview() {
        app.buttons["host.import"].tap(); selectDirectory()
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
        XCTAssertTrue(browser.waitForExistence(timeout:20),app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:60),app.debugDescription)
    }
}

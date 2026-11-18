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
    private func selectExternalDirectory() {
        XCTAssertTrue(navigation.waitForExistence(timeout:60),app.debugDescription)
        let title = "Void Files QA"
        let container = app.cells.matching(NSPredicate(format:"label BEGINSWITH[c] %@ OR identifier BEGINSWITH[c] %@",title,title)).firstMatch
        let manifestFolder = app.cells.matching(NSPredicate(format:"label BEGINSWITH[c] %@", "app,")).firstMatch
        if !manifestFolder.exists {
            if !container.exists {
                let browse = named(["Browse","浏览"],in:app.tabBars.buttons)
                let local = app.cells["DOC.sidebar.item.On My iPhone"].firstMatch
                if !local.exists && browse.exists { browse.tap() }
                if !local.exists && !container.exists {
                    let back = app.buttons["DOC.navBarButton.backInHistory"].firstMatch
                    if browse.exists && browse.isSelected { browse.tap() }
                    else if back.exists && back.isEnabled { back.tap() }
                }
                if local.waitForExistence(timeout:5) && local.isHittable { local.tap() }
            }
            XCTAssertTrue(container.waitForExistence(timeout:45),app.debugDescription)
            container.tap()
            if !manifestFolder.waitForExistence(timeout:8), container.exists && container.isHittable {
                container.doubleTap()
            }
            XCTAssertTrue(manifestFolder.waitForExistence(timeout:30),app.debugDescription)
        }
        pressSystemOpen()
    }

    private func pressSystemOpen() {
        let selectable = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND enabled == true"),object:openButton)
        XCTAssertEqual(XCTWaiter.wait(for:[selectable],timeout:30),.completed,app.debugDescription)
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
        // Drag the actual UIKit grabber. Files exposes an out-of-process Cancel element
        // whose accessibility action has itself timed out on the CI simulator.
        let handle = named(["Sheet Grabber","表单抓取按钮"],in:app.buttons)
        XCTAssertTrue(handle.waitForExistence(timeout:60),app.debugDescription)
        let frame = handle.frame
        XCTAssertFalse(frame.isEmpty)
        let origin = app.coordinate(withNormalizedOffset:.zero)
        let top = origin.withOffset(CGVector(dx:frame.midX,dy:frame.midY))
        let bottom = app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.95))
        top.press(forDuration:0.15,thenDragTo:bottom)
        let gone = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:handle)
        XCTAssertEqual(XCTWaiter.wait(for:[gone],timeout:25),.completed,app.debugDescription)
        let done = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","已取消目录操作"),object:app.staticTexts["folder.status"])
        XCTAssertEqual(XCTWaiter.wait(for:[done],timeout:12),.completed,app.debugDescription)
        app.buttons["folder.clear"].tap()
    }

    private func openLibrary(localFixture: Bool = true) {
        continueAfterFailure = false
        executionTimeAllowance = 360
        if localFixture { app.launchEnvironment["VOID_PICKER_TEST_PROJECT"] = token }
        app.launch()
        if !app.buttons["host.import"].waitForExistence(timeout:3) {
            app.buttons["host.manage"].tap(); app.buttons["host.switch"].tap()
        }
        XCTAssertFalse(app.buttons["recent." + (localFixture ? fixture : "我的项目")].exists)
    }
    private func importAndPreview() {
        app.buttons["host.import"].tap(); selectExternalDirectory()
        let status = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","已找到「我的项目」"),object:app.staticTexts["folder.status"])
        XCTAssertEqual(XCTWaiter.wait(for:[status],timeout:25),.completed,app.debugDescription)
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:70),app.debugDescription)
    }
    private func reconnect() {
        app.buttons["host.manage"].tap(); app.buttons["host.reconnect"].tap()
    }

    private func scanDocumentsAndPreview() {
        app.buttons["host.local"].tap()
        previewDiscoveredFixture()
    }

    private func previewDiscoveredFixture() {
        let status = app.staticTexts["folder.status"]
        let found = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label BEGINSWITH %@", "已找到"),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[found],timeout:45),.completed,app.debugDescription)
        if status.label != "已找到「" + fixture + "」" {
            let original = app.buttons["recent." + fixture]
            XCTAssertTrue(original.waitForExistence(timeout:8),app.debugDescription)
            original.tap()
        }
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:70),app.debugDescription)
    }

    func testDocumentsScanImportsAndPreviewsUnregisteredTSX() {
        openLibrary()
        scanDocumentsAndPreview()
        app.buttons["host.manage"].tap()
        app.buttons["host.rescan"].tap()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:30),app.debugDescription)
    }

    func testSystemOpenPreviewsProjectFromSelectedDocumentsDirectory() {
        openLibrary()
        app.buttons["host.import"].tap()
        pressSystemOpen()
        // Files may start at the parent of directoryURL. A parent import must expose
        // this previously unregistered project's row before it can be opened.
        previewDiscoveredFixture()
    }

    func testSystemOpenImportsPreviewsAndReconnectsOriginal() {
        openLibrary(localFixture:false)
        importAndPreview()
        reconnect(); selectExternalDirectory()
        expectation(for:NSPredicate(format:"label == %@", "已核验原项目目录"),evaluatedWith:app.staticTexts["folder.status"])
        waitForExpectations(timeout:25)
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:30),app.debugDescription)
    }

    func testInterruptedFirstFrameReturnsToOriginalProjectList() {
        app.launchEnvironment["VOID_TEST_SLOW_FIRST_FRAME"] = "1"
        openLibrary()
        app.buttons["host.local"].tap()
        let status = app.staticTexts["folder.status"]
        let found = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label BEGINSWITH %@", "已找到"),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[found],timeout:45),.completed,app.debugDescription)
        if status.label != "已找到「" + fixture + "」" { app.buttons["recent." + fixture].tap() }
        let stage = app.staticTexts["preview.stage"]
        let frame = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@", "正在等待项目首屏"),object:stage)
        XCTAssertEqual(XCTWaiter.wait(for:[frame],timeout:100),.completed,app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["preview.interrupted"].waitForExistence(timeout:30),app.debugDescription)
        let record = app.buttons["recent." + fixture]
        XCTAssertTrue(record.exists)
        record.tap()
        XCTAssertTrue(app.staticTexts["预览已恢复"].waitForExistence(timeout:120),app.debugDescription)
    }

    func testSystemDismissalAndInterruptionKeepPreviousProject() {
        openLibrary()
        app.buttons["host.import"].tap(); cancelPicker()
        scanDocumentsAndPreview()
        reconnect(); cancelPicker()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.exists,app.debugDescription)
        reconnect()
        XCTAssertTrue(navigation.waitForExistence(timeout:60),app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:60),app.debugDescription)
    }
}

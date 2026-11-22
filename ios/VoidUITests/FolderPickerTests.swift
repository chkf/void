import XCTest

final class FolderPickerTests: XCTestCase {
    private let app = XCUIApplication()
    private var token = UUID().uuidString
    private var fixture: String { "Void Picker " + String(token.prefix(8)) }
    private var externalFixture: String { ProcessInfo.processInfo.environment["VOID_EXTERNAL_PROJECT"] ?? "Void Files QA" }

    private func named(_ labels: [String], in elements: XCUIElementQuery) -> XCUIElement {
        elements.matching(NSPredicate(format:"label IN %@ OR identifier IN %@",labels,labels)).firstMatch
    }
    private var navigation: XCUIElement { app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].firstMatch }
    private var openButton: XCUIElement { app.buttons["DOCPicker.actionButton"].firstMatch }
    private func folderCell(_ name: String) -> XCUIElement {
        app.cells.matching(NSPredicate(format: "label ==[c] %@ OR label BEGINSWITH[c] %@ OR identifier ==[c] %@",
                                       name, name + ",", name)).firstMatch
    }

    private func browseOnMyIPhone() {
        let local = app.cells["DOC.sidebar.item.On My iPhone"].firstMatch
        let browse = named(["Browse", "浏览"], in: app.tabBars.buttons)
        if !local.exists && browse.exists { browse.tap() }
        if !local.waitForExistence(timeout: 3) {
            if browse.exists && browse.isSelected { browse.tap() }
            else {
                let back = app.buttons["DOC.navBarButton.backInHistory"].firstMatch
                if back.exists && back.isEnabled { back.tap() }
            }
        }
        if local.waitForExistence(timeout: 5) && local.isHittable { local.tap() }
    }

    private func listViewInFiles() {
        let more = navigation.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] %@ OR label IN %@",
                                                           "more", ["More", "View Options", "更多", "显示选项"])).firstMatch
        guard more.exists && more.isHittable else { return }
        more.tap()
        let list = named(["List", "列表"], in: app.buttons)
        if list.waitForExistence(timeout: 3) { list.tap() }
        else { navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap() }
    }

    private func openProjectDirectory(_ title: String, inAppDocuments: Bool = false) {
        XCTAssertTrue(navigation.waitForExistence(timeout: 60), app.debugDescription)
        let project = folderCell(title)
        let source = folderCell("app")
        let current = navigation.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        if !(current.exists && source.exists) {
            let documents = folderCell("void")
            if !project.exists && !(inAppDocuments && documents.exists) { browseOnMyIPhone() }
            if inAppDocuments && !project.exists {
                listViewInFiles()
                XCTAssertTrue(documents.waitForExistence(timeout: 30), app.debugDescription)
                documents.tap()
                if !project.waitForExistence(timeout: 20), documents.exists && documents.isHittable {
                    documents.doubleTap()
                }
            }
            XCTAssertTrue(project.waitForExistence(timeout: 35), app.debugDescription)
            project.tap()
            if !source.waitForExistence(timeout: 12), project.exists && project.isHittable && !project.isSelected {
                project.doubleTap()
            }
            // Some Files views select the row, others show the project's contents.
            // The imported identity and the actual on-disk folder are checked after Open.
            XCTAssertTrue((project.exists && project.isSelected) || source.waitForExistence(timeout: 25), app.debugDescription)
        }
        pressSystemOpen()
    }

    private func pressSystemOpen() {
        XCTAssertTrue(navigation.waitForExistence(timeout:60),app.debugDescription)
        let selectable = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND enabled == true"),object:openButton)
        XCTAssertEqual(XCTWaiter.wait(for:[selectable],timeout:60),.completed,app.debugDescription)
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
    private func cancelPicker(returningTo control: XCUIElement, preferSwipe: Bool = false) {
        XCTAssertTrue(navigation.waitForExistence(timeout:60),app.debugDescription)
        let cancel = named(["Cancel","取消","Close","关闭"], in: navigation.buttons)
        let handle = named(["Sheet Grabber","表单抓取按钮"],in:app.buttons)
        if handle.exists && (preferSwipe || !cancel.isHittable) {
            let top = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            top.press(forDuration:0.15,thenDragTo:bottom)
        } else {
            XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
            cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(navigation.waitForNonExistence(timeout: 25), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 12), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["folder.status"].exists)
        XCTAssertFalse(app.buttons["folder.clear"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    private func openLibrary(localFixture: Bool = true) {
        continueAfterFailure = false
        executionTimeAllowance = 360
        if localFixture { app.launchEnvironment["VOID_PICKER_TEST_PROJECT"] = token }
        let arguments = app.launchArguments
        app.launchArguments += ["-void.openProjectListOnLaunch", "YES"]
        app.launch()
        app.launchArguments = arguments
        XCTAssertTrue(app.buttons["host.import"].waitForExistence(timeout: 12), app.debugDescription)
        if localFixture {
            let ready = app.buttons.matching(NSPredicate(format:"identifier == %@ AND value == %@",
                                                          "host.import","fixture-ready")).firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout:40),app.debugDescription)
        }
    }
    private func importAndPreview() {
        app.buttons["host.import"].tap()
        openProjectDirectory(externalFixture)
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:95),app.debugDescription)
        XCTAssertFalse(app.staticTexts["folder.status"].exists)
    }
    private func launchFixture() {
        let row = app.buttons["project.row." + fixture]
        XCTAssertTrue(app.revealRecentProject(row), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.alerts["启动项目？"].waitForExistence(timeout:12),app.debugDescription)
        XCTAssertFalse(app.staticTexts["folder.status"].exists)
        XCTAssertFalse(app.staticTexts["preview.stage"].exists)
        app.confirmProjectLaunch()
    }

    func testDocumentsProjectAppearsAutomaticallyAndWaitsForPreview() {
        openLibrary()
        launchFixture()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:70),app.debugDescription)
        app.returnToProjectList()
    }

    func testSystemOpenPreviewsProjectFromSelectedDocumentsDirectory() throws {
        if let existing = ProcessInfo.processInfo.environment["VOID_EXISTING_PICKER_PROJECT"] {
            token = try XCTUnwrap(UUID(uuidString:existing)).uuidString
        }
        openLibrary()
        app.buttons["host.import"].tap()
        openProjectDirectory(fixture, inAppDocuments: true)
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:120),app.debugDescription)
        XCTAssertFalse(app.staticTexts["folder.status"].exists)
        app.returnToProjectList()
        XCTAssertTrue(app.buttons["project.row." + fixture].waitForExistence(timeout:12),app.debugDescription)
    }

    func testSystemOpenImportsExternalCopyAndReopensIt() {
        openLibrary(localFixture:false)
        importAndPreview()
        XCTAssertTrue(app.buttons["scan.cancel"].waitForNonExistence(timeout: 25), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:55),app.debugDescription)
        app.returnToProjectList()
        XCTAssertTrue(app.revealRecentProject(app.buttons["project.row." + externalFixture]), app.debugDescription)
    }

    func testInterruptedFirstFrameReturnsToOriginalProjectList() {
        app.launchEnvironment["VOID_TEST_SLOW_FIRST_FRAME"] = "1"
        openLibrary()
        launchFixture()
        let stage = app.staticTexts["preview.stage"]
        let frame = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@", "正在等待项目首屏"),object:stage)
        XCTAssertEqual(XCTWaiter.wait(for:[frame],timeout:100),.completed,app.debugDescription)
        app.terminate()
        app.launch()
        let interruption = app.staticTexts["preview.interrupted"]
        XCTAssertTrue(interruption.waitForExistence(timeout:30),app.debugDescription)
        XCTAssertTrue(interruption.label.contains(fixture))
        XCTAssertFalse(app.buttons["上次预览诊断"].exists)
        let record = app.buttons["project.row." + fixture]
        XCTAssertTrue(record.exists)
        launchFixture()
        XCTAssertTrue(app.staticTexts["预览已恢复"].waitForExistence(timeout:120),app.debugDescription)
    }

    func testCancelledAndInterruptedFolderSelectionReturnsToProjectList() {
        openLibrary()
        let create = app.buttons["host.create"]
        create.tap()
        let field = app.textFields["project.name"]
        field.tap()
        field.typeText("Folder-" + String(token.prefix(8)))
        app.buttons["选择其他文件夹…"].tap()
        cancelPicker(returningTo: create)
        app.buttons["host.import"].tap()
        cancelPicker(returningTo: app.buttons["host.import"], preferSwipe: true)
        launchFixture()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:70),app.debugDescription)
        app.returnToProjectList()
        app.buttons["host.import"].tap()
        XCTAssertTrue(navigation.waitForExistence(timeout:60),app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["host.import"].waitForExistence(timeout:12),app.debugDescription)
        XCTAssertTrue(app.revealRecentProject(app.buttons["project.row." + fixture]))
    }
}

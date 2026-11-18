import XCTest

final class FolderPickerTests: XCTestCase {
    private let app = XCUIApplication()
    private let fixture = "Void Picker Test"

    private func named(_ labels: [String], in elements: XCUIElementQuery) -> XCUIElement {
        elements.matching(NSPredicate(format:"label IN %@ OR identifier IN %@",labels,labels)).firstMatch
    }
    private func pickerButton(_ names: [String]) -> XCUIElement { named(names,in:app.buttons) }
    private func selectDirectory() {
        let folder = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@ OR label BEGINSWITH %@",fixture,fixture + ",")).firstMatch
        if !folder.waitForExistence(timeout:5) {
            let browse = pickerButton(["Browse","浏览"])
            if browse.exists { browse.tap() }
            let local = named(["On My iPhone","我的 iPhone","在我的 iPhone 上"],in:app.descendants(matching:.any))
            if local.waitForExistence(timeout:5) { local.tap() }
            let host = named(["void","Void"],in:app.descendants(matching:.any))
            if host.waitForExistence(timeout:4) { host.tap() }
        }
        XCTAssertTrue(folder.waitForExistence(timeout:15),app.debugDescription)
        folder.tap()
        let open = pickerButton(["Open","打开","选取","Choose","Select","Done","完成"])
        XCTAssertTrue(open.waitForExistence(timeout:10),app.debugDescription)
        open.tap()
    }

    func testSystemPickerImportCancelOpenPreviewAndReconnect() {
        continueAfterFailure = false
        app.launch()
        let importFolder = app.buttons["host.import"]
        if !importFolder.waitForExistence(timeout:3) {
            app.buttons["host.manage"].tap(); app.buttons["host.switch"].tap()
        }
        let cancelled = app.staticTexts["folder.status"]
        func cancelPicker() {
            let button = pickerButton(["Cancel","取消","Close","关闭"])
            XCTAssertTrue(button.waitForExistence(timeout:15),app.debugDescription)
            button.tap()
            expectation(for:NSPredicate(format:"label == %@", "已取消目录操作"),evaluatedWith:cancelled)
            waitForExpectations(timeout:12)
            app.buttons["folder.clear"].tap()
        }
        importFolder.tap(); cancelPicker()
        importFolder.tap(); selectDirectory()
        let native = app.switches["显示问候"].firstMatch
        XCTAssertTrue(native.waitForExistence(timeout:70),app.debugDescription)
        app.buttons["host.manage"].tap(); app.buttons["host.reconnect"].tap(); cancelPicker()
        XCTAssertTrue(native.exists,app.debugDescription)
        app.buttons["host.manage"].tap(); app.buttons["host.reconnect"].tap(); selectDirectory()
        expectation(for:NSPredicate(format:"label == %@", "已核验原项目目录"),evaluatedWith:app.staticTexts["folder.status"])
        waitForExpectations(timeout:25)
        XCTAssertTrue(native.waitForExistence(timeout:30),app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(native.waitForExistence(timeout:60),app.debugDescription)
    }
}

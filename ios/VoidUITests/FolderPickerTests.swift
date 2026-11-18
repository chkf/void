import Vision
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
        if localFixture {
            let ready = app.buttons.matching(NSPredicate(format:"identifier IN %@ AND value == %@",
                                                          ["host.import","host.manage"],"fixture-ready")).firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout:40),app.debugDescription)
        }
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

    private func openFixtureOverview() {
        let row = app.buttons["recent." + fixture]
        XCTAssertTrue(row.waitForExistence(timeout:12),app.debugDescription)
        row.tap()
        let preview = app.buttons["project.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout:12),app.debugDescription)
        XCTAssertFalse(app.staticTexts["preview.stage"].exists)
        preview.tap()
    }

    private func scanDocumentsAndPreview() {
        app.buttons["host.local"].tap()
        let status = app.staticTexts["folder.status"]
        let found = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label BEGINSWITH %@", "已找到"),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[found],timeout:45),.completed,app.debugDescription)
        openFixtureOverview()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:70),app.debugDescription)
    }

    func testDocumentsScanImportsAndPreviewsUnregisteredTSX() {
        openLibrary()
        scanDocumentsAndPreview()
        app.buttons["host.manage"].tap()
        app.buttons["host.rescan"].tap()
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:30),app.debugDescription)
    }

    // This exercises Apple's visible system button without waiting on the accessibility
    // tree of the out-of-process Files extension. The host result and TSX frame are
    // still asserted separately and the directory comes from the real picker delegate.
    private func tapVisiblePickerText(_ labels: Set<String>, topRight: Bool, timeout: TimeInterval) throws -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            let screenshot = XCUIScreen.main.screenshot()
            let image = try XCTUnwrap(screenshot.image.cgImage)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US","zh-Hans"]
            try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
            for line in request.results ?? [] {
                let box = line.boundingBox
                if topRight && (box.midX < 0.60 || box.midY < 0.72) { continue }
                let text = line.topCandidates(1).first?.string
                    .trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters)).lowercased() ?? ""
                if labels.contains(text) {
                    app.coordinate(withNormalizedOffset:CGVector(dx:box.midX,dy:1-box.midY)).tap()
                    return true
                }
            }
            RunLoop.current.run(until:Date().addingTimeInterval(0.4))
        } while Date() < end
        return false
    }

    func testSystemOpenPreviewsProjectFromSelectedDocumentsDirectory() throws {
        openLibrary()
        app.buttons["host.import"].tap()
        guard try tapVisiblePickerText(["open","打开"],topRight:true,timeout:60) else {
            let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            shot.name = "系统选择器未显示可识别的 Open"; shot.lifetime = .keepAlways; add(shot)
            XCTFail("等待系统 Files 的 Open 按钮超时")
            return
        }
        _ = try tapVisiblePickerText(["allow","允许"],topRight:false,timeout:4)
        let selected = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","已找到「" + fixture + "」"),
                                                  object:app.staticTexts["folder.status"])
        XCTAssertEqual(XCTWaiter.wait(for:[selected],timeout:35),.completed,app.debugDescription)
        XCTAssertTrue(app.switches["显示问候"].firstMatch.waitForExistence(timeout:85),app.debugDescription)
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
        openFixtureOverview()
        let stage = app.staticTexts["preview.stage"]
        let frame = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@", "正在等待项目首屏"),object:stage)
        XCTAssertEqual(XCTWaiter.wait(for:[frame],timeout:100),.completed,app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["preview.interrupted"].waitForExistence(timeout:30),app.debugDescription)
        let record = app.buttons["recent." + fixture]
        XCTAssertTrue(record.exists)
        openFixtureOverview()
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

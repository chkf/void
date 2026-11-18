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

    private struct VisiblePickerLabel {
        let text: String
        let point: CGPoint
    }

    private func pickerLabels() throws -> [VisiblePickerLabel] {
        let image = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US","zh-Hans"]
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        return (request.results ?? []).compactMap { line in
            guard let candidate = line.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
            let box = line.boundingBox
            return VisiblePickerLabel(text:text,point:CGPoint(x:box.midX,y:1-box.midY))
        }
    }

    private func tap(_ label: VisiblePickerLabel) {
        app.coordinate(withNormalizedOffset:CGVector(dx:label.point.x,dy:label.point.y)).tap()
    }

    // Files treats directoryURL as a hint. Navigate its visible folders and verify
    // the app/ child before opening, even when the provider starts at another level.
    private func pickLocalProjectInFiles() throws {
        let end = Date().addingTimeInterval(90)
        var lastScreen: [String] = []
        repeat {
            let labels = try pickerLabels()
            let open = labels.first { ["open","打开"].contains($0.text) && $0.point.x > 0.6 && $0.point.y < 0.3 }
            let entries = labels.filter { $0.point.y > 0.19 && $0.point.y < 0.9 }
            let screen = labels.map(\.text)
            if screen != lastScreen {
                print("Files simulator screen",screen.prefix(40))
                lastScreen = screen
            }
            let atFixture = labels.contains { $0.point.y < 0.19 && ($0.text.contains("void picker") || $0.text.contains(String(token.prefix(8)).lowercased())) }
            let hasSourceFolder = entries.contains { $0.text == "app" }
            let hasManifestSibling = entries.contains { ["runtime.json","runtime","assets","modules"].contains($0.text) }
            if let open, hasSourceFolder || (atFixture && hasManifestSibling) {
                tap(open)
                return
            }
            if atFixture {
                RunLoop.current.run(until:Date().addingTimeInterval(1))
                continue
            }
            let fixtureRow = entries.first { $0.text.contains("void picker") || $0.text == String(token.prefix(8)).lowercased() }
            let container = entries.first { $0.text == "void" }
            let location = entries.first { ["on my iphone","我的 iphone","我的iphone"].contains($0.text) }
            let browse = labels.first { ["browse","浏览"].contains($0.text) && ($0.point.x < 0.3 || $0.point.y > 0.9) }
            if let destination = fixtureRow ?? container ?? location ?? browse { tap(destination) }
            RunLoop.current.run(until:Date().addingTimeInterval(1))
        } while Date() < end
        let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        shot.name = "本机 Files 导航最后画面"; shot.lifetime = .keepAlways; add(shot)
        XCTFail("Files 尚未在测试项目目录显示 app 和 Open")
    }

    func testSystemOpenPreviewsProjectFromSelectedDocumentsDirectory() throws {
        openLibrary()
        app.buttons["host.import"].tap()
        try pickLocalProjectInFiles()
        let end = Date().addingTimeInterval(5)
        repeat {
            if let allow = try pickerLabels().first(where:{ ["allow","允许"].contains($0.text) }) { tap(allow); break }
        } while Date() < end
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

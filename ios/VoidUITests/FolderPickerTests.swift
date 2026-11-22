import Vision
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
    private func selectExternalDirectory() {
        XCTAssertTrue(navigation.waitForExistence(timeout:60),app.debugDescription)
        let title = externalFixture
        let container = app.cells.matching(NSPredicate(format:"label BEGINSWITH[c] %@ OR identifier BEGINSWITH[c] %@",title,title)).firstMatch
        let manifestFolder = app.cells.matching(NSPredicate(format:"label BEGINSWITH[c] %@", "app,")).firstMatch
        let currentFolder = navigation.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        if !currentFolder.exists || !manifestFolder.exists {
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
        app.buttons["host.import"].tap(); selectExternalDirectory()
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

    private func coordinate(_ label: VisiblePickerLabel) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset:CGVector(dx:label.point.x,dy:label.point.y))
    }

    private func pickerCell(named name: String) -> XCUIElement {
        app.cells.matching(NSPredicate(format: "label ==[c] %@ OR label BEGINSWITH[c] %@ OR identifier ==[c] %@",
                                       name, name + ",", name)).firstMatch
    }

    // Files treats directoryURL as a hint. Navigate its visible folders and verify
    // the app/ child before opening, even when the provider starts at another level.
    private func pickLocalProjectInFiles() throws {
        let started = Date()
        let end = started.addingTimeInterval(105)
        var lastScreen: [String] = []
        var lastFolder: String?
        var searched = false
        repeat {
            let labels = try pickerLabels()
            let open = labels.first { ["open","打开"].contains($0.text) && $0.point.x > 0.6 && $0.point.y < 0.3 }
            let searchY = labels.first { $0.point.y < 0.3 && ($0.text.contains("search") || $0.text.contains("搜索")) }?.point.y ?? 0.16
            let entries = labels.filter { $0.point.y > searchY + 0.015 && $0.point.y < 0.9 }
            let screen = labels.map(\.text)
            if screen != lastScreen {
                print("Files simulator screen",screen.prefix(40))
                lastScreen = screen
            }
            let atFixture = !searched && labels.contains { $0.point.y < searchY && ($0.text.contains("void picker") || $0.text.contains(String(token.prefix(8)).lowercased())) }
            let hasSourceFolder = entries.contains { $0.text == "app" }
            let hasManifestSibling = entries.contains { ["runtime.json","runtime","assets","modules"].contains($0.text) }
            if let open, hasSourceFolder || (atFixture && hasManifestSibling) {
                coordinate(open).tap()
                return
            }
            // A freshly launched provider initially draws Recents while resolving its start URL.
            if atFixture || Date().timeIntervalSince(started) < 12 {
                RunLoop.current.run(until:Date().addingTimeInterval(1))
                continue
            }
            let fixtureRow = entries.first { $0.text.contains("void picker") || $0.text == String(token.prefix(8)).lowercased() }
            let container = entries.first { $0.text == "void" }
            let location = entries.first { ["on my iphone","我的 iphone","我的iphone"].contains($0.text) }
            let browse = labels.first { ["browse","浏览"].contains($0.text) && ($0.point.x < 0.3 || $0.point.y > 0.9) }
            if let folder = fixtureRow ?? container {
                // On a fresh simulator the app's container tile can stay on screen after a tap.
                // Search the current Files location for the exact seeded project in that case.
                if folder.text == "void", lastFolder == folder.text, !searched {
                    let field = app.searchFields.firstMatch
                    if field.exists && field.isHittable {
                        field.tap()
                        field.typeText(fixture + "\n")
                        searched = true
                        lastFolder = nil
                        continue
                    }
                }
                let cell = pickerCell(named: fixtureRow == nil ? "void" : fixture)
                if cell.exists && cell.isHittable {
                    if fixtureRow != nil && cell.isSelected, let open { coordinate(open).tap(); return }
                    if lastFolder == folder.text { cell.doubleTap() } else { cell.tap() }
                    lastFolder = folder.text
                    RunLoop.current.run(until: Date().addingTimeInterval(1))
                    continue
                }
                // In Files' icon view the caption can receive taps for renaming. The
                // separate item count below it identifies a tile; open its thumbnail.
                let caption = entries.first {
                    let delta = $0.point.y - folder.point.y
                    return abs($0.point.x - folder.point.x) < 0.045 && delta > 0 && delta < 0.045
                        && ($0.text.hasSuffix(" item") || $0.text.hasSuffix(" items") || $0.text.hasSuffix("项"))
                }
                var target = coordinate(folder)
                if let caption {
                    let lineHeight = (caption.point.y - folder.point.y) * app.frame.height
                    target = target.withOffset(CGVector(dx: 0, dy: -min(54, max(30, 2.6 * lineHeight))))
                }
                if lastFolder == folder.text { target.doubleTap() } else { target.tap() }
                lastFolder = folder.text
            } else if let place = location ?? browse {
                coordinate(place).tap()
                lastFolder = nil
            }
            RunLoop.current.run(until:Date().addingTimeInterval(1))
        } while Date() < end
        let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        shot.name = "本机 Files 导航最后画面"; shot.lifetime = .keepAlways; add(shot)
        XCTFail("Files 尚未在测试项目目录显示 app 和 Open")
    }

    func testSystemOpenPreviewsProjectFromSelectedDocumentsDirectory() throws {
        if let existing = ProcessInfo.processInfo.environment["VOID_EXISTING_PICKER_PROJECT"] {
            token = try XCTUnwrap(UUID(uuidString:existing)).uuidString
        }
        openLibrary()
        app.buttons["host.import"].tap()
        try pickLocalProjectInFiles()
        let end = Date().addingTimeInterval(5)
        repeat {
            if let allow = try pickerLabels().first(where:{ ["allow","允许"].contains($0.text) }) { coordinate(allow).tap(); break }
        } while Date() < end
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

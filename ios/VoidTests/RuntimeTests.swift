import SwiftUI
import XCTest
@testable import VoidHost

@MainActor
final class PreviewTestWindow {
    let window: UIWindow
    private let previousRoot: UIViewController?
    private let hostController: UIHostingController<HostView>

    init(_ host: HostModel) async throws {
        await host.load()
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        window = try XCTUnwrap(scenes.flatMap { $0.windows }.first(where:{ $0.isKeyWindow }))
        previousRoot = window.rootViewController
        hostController = UIHostingController(rootView:HostView(model:host))
        window.rootViewController = hostController
        window.layoutIfNeeded()
    }

    func close() {
        if window.rootViewController === hostController { window.rootViewController = previousRoot }
    }
}

@MainActor
final class RuntimeTests: XCTestCase {
    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RuntimeIssue("等待项目会话超时") }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    func testExistingSwiftUIWorkspaceReopensAndDetectsEditsThatNeedANewBuild() async throws {
        let name = "SwiftUI-" + UUID().uuidString
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let project = FolderGrant.documents.appendingPathComponent(name)
        defer {
            try? FileManager.default.removeItem(at: storage)
            try? FileManager.default.removeItem(at: project)
        }
        let sourceFolder = try XCTUnwrap(Bundle.main.url(forResource: "StarterProject", withExtension: nil))
        try FileManager.default.copyItem(at: sourceFolder, to: project)
        let library = ProjectLibrary(base: storage)
        let discovered = try await library.discover(project)
        var record = try XCTUnwrap(discovered.first)
        record.pendingTemplate = .swiftUI
        let catalog = Catalog(records: [record], last: record.id)
        try JSONEncoder().encode(catalog).write(to: storage.appendingPathComponent("projects.json"), options: .atomic)
        let host = HostModel(storage: storage)
        await host.load()
        XCTAssertEqual(host.workspaceTemplate, .swiftUI)
        XCTAssertNil(host.problem)
        host.refresh(force: true)
        try await wait { (host.workspaceTemplate == nil && host.screen != nil) || host.problem != nil || host.notice != nil }
        guard case let .swiftUI(original)? = host.screen else { return XCTFail(host.problem ?? host.notice ?? "缺少 SwiftUI 页面") }
        XCTAssertNil(host.page)
        XCTAssertNil(host.candidate)
        let entry = project.appendingPathComponent("app/" + CompiledProject.entry)
        let source = try String(contentsOf: entry, encoding: .utf8)
        try (source + "\n// 外部编辑\n").write(to: entry, atomically: true, encoding: .utf8)
        host.refresh()
        try await wait { host.problem != nil }
        XCTAssertTrue(host.problem?.contains("GitHub Actions") == true)
        guard case let .swiftUI(current)? = host.screen else { return XCTFail("已打开的页面应保留") }
        XCTAssertEqual(current, original)
        await host.showLibrary()
        await host.open(try XCTUnwrap(host.records.first))
        try await wait { host.problem != nil }
        XCTAssertNil(host.screen)
        try source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
            .write(to: entry, atomically: true, encoding: .utf8)
        host.refresh()
        try await wait { host.screen != nil }
        XCTAssertNil(host.problem)
        XCTAssertNil(host.page)
        await host.showLibrary()
    }

    func testReactProjectCreatedInSelectedFolderCanReadItsDataAfterReopening() async throws {
        let name = "TSXFiles-" + UUID().uuidString
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let parent = FolderGrant.documents.appendingPathComponent(name)
        let project = parent.appendingPathComponent("笔记")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storage); try? FileManager.default.removeItem(at: parent) }
        let host = HostModel(storage: storage)
        await host.load()
        let request = host.folders.begin(.create("笔记"), origin: nil, afterSheet: true)
        host.folders.sheetClosed()
        host.folders.didPresent(request.id)
        host.folders.picked(request.id, [parent])
        host.folders.dismissed(request.id)
        try await wait { !host.folders.active }
        XCTAssertEqual(host.folders.phase, .succeeded, host.folders.message)
        XCTAssertEqual(host.workspaceTemplate, .tsx)
        let window = try await PreviewTestWindow(host)
        defer { window.close() }
        XCTAssertEqual(Set(host.permissions), ["files.read", "files.write"])
        let record = try XCTUnwrap(host.current)
        let reference = try String(contentsOf:project.appendingPathComponent("SDK_REFERENCE.md"),encoding:.utf8)
        XCTAssertTrue(reference.contains("ios.fs.readFile"))
        XCTAssertTrue(FileManager.default.fileExists(atPath:project.appendingPathComponent("types/runtime-sdk.d.ts").path))
        for key in ["files.read", "files.write"] { SDKConsent.shared.set(true, for: key, project: record.id) }
        defer { for key in ["files.read", "files.write"] { SDKConsent.shared.set(nil, for:key, project: record.id) } }
        let source = """
        import {render, Text} from "@runtime/ui";
        import {ios} from "@runtime/sdk";
        async function start() {
          const path = "data/notes/first.txt";
          const before = await ios.fs.exists({path});
          if (!before.success) throw Error(before.error.message);
          if (!before.data) {
            const response = await ios.fs.writeFile({path, data:"下次见"});
            if (!response.success) throw Error(response.error.message);
          }
          const saved = await ios.fs.readFile({path});
          if (!saved.success) throw Error(saved.error.message);
          render(<Text value={(before.data ? "重开" : "创建") + saved.data} />);
        }
        start().catch(error => render(<Text value={String(error)} />));
        """
        try Data(source.utf8).write(to: project.appendingPathComponent("app/src/main.tsx"), options:.atomic)
        host.refresh(force:true)
        try await wait { host.page != nil || host.problem != nil }
        XCTAssertEqual(host.page?.nodes.first?.text("value"), "创建下次见", host.problem ?? "")
        XCTAssertEqual(try String(contentsOf:project.appendingPathComponent("data/notes/first.txt"), encoding:.utf8),"下次见")
        await host.showLibrary()
        let reopened = HostModel(storage:storage)
        let nextWindow = try await PreviewTestWindow(reopened)
        defer { nextWindow.close() }
        await reopened.open(try XCTUnwrap(reopened.records.first))
        try await wait { reopened.page != nil || reopened.problem != nil }
        XCTAssertEqual(reopened.page?.nodes.first?.text("value"), "重开下次见", reopened.problem ?? "")
        await reopened.showLibrary()
    }

    func testIncompleteImportedProjectWaitsForItsFirstPage() async throws {
        let dir = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir); try? FileManager.default.removeItem(at:storage) }
        let app = dir.appendingPathComponent("app")
        try FileManager.default.createDirectory(at:app,withIntermediateDirectories:true)
        try Data(#"{"name":"空白项目","uiMode":"web","entry":"index.html"}"#.utf8).write(to:app.appendingPathComponent("manifest.json"))
        let host = HostModel(storage:storage)
        let window = try await PreviewTestWindow(host)
        defer { window.close() }
        await host.importDirectory(dir)
        try await wait { host.waitingEntry != nil || host.notice != nil }
        XCTAssertEqual(host.waitingEntry,"app/index.html")
        let html = #"<main>第一页</main><a href="void://project/management">项目管理</a>"#
        try Data(html.utf8).write(to:app.appendingPathComponent("index.html"))
        host.refresh()
        try await wait { host.page != nil }
        XCTAssertNil(host.waitingEntry)
        XCTAssertNil(host.problem)
        let page = try XCTUnwrap(host.page)
        _ = try await page.view.evaluateJavaScript("setTimeout(() => document.querySelector('a').click(), 0); true")
        try await wait { host.current == nil }
        XCTAssertNil(host.page)
        XCTAssertNil(window.window.rootViewController?.presentedViewController)
        XCTAssertTrue(host.records.contains { $0.name == "空白项目" })
    }

    func testBrokenEditKeepsNativePageAndProjectCanBeReopened() async throws {
        let name = "RuntimeTests-" + UUID().uuidString
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let project = FolderGrant.documents.appendingPathComponent(name)
        defer {
            try? FileManager.default.removeItem(at: storage)
            try? FileManager.default.removeItem(at: project)
        }
        let host = HostModel(storage: storage)
        let window = try await PreviewTestWindow(host)
        defer { window.close() }
        await host.create(name, parent: nil)
        XCTAssertEqual(host.workspaceTemplate, .tsx)
        host.refresh(force: true)
        try await wait { host.page != nil || host.problem != nil || host.notice != nil }
        let beforeWarning = try XCTUnwrap(host.page,host.problem ?? host.notice ?? "")
        XCTAssertEqual(beforeWarning.nodes.first?.type,"Form")
        host.refresh(force:true)
        host.memoryWarning()
        try await wait { !host.busy }
        XCTAssertEqual(host.page?.id,beforeWarning.id)
        XCTAssertTrue(host.problem?.contains("内存") == true)
        host.refresh(force:true,remember:true)
        try await wait { !host.busy }
        let original = try XCTUnwrap(host.page,host.problem ?? "")
        XCTAssertEqual(original.nodes.first?.type,"Form")
        let toggle = try XCTUnwrap(original.nodes.first?.children.first?.children.first { $0.type == "Toggle" })
        let sequence = original.event(toggle.id, name: "onChange", value: false)
        try await wait { original.acknowledged >= sequence || host.problem != nil }
        XCTAssertNil(host.problem)
        let children = try XCTUnwrap(original.nodes.first?.children.first?.children)
        XCTAssertEqual(children.first { $0.type == "Toggle" }?.flag, false)
        XCTAssertFalse(children.contains { $0.type == "Text" })
        let source = project.appendingPathComponent("app/src/main.tsx")
        let saved = try Data(contentsOf: source)
        try Data("const broken: number = '无效';".utf8).write(to: source, options: .atomic)
        host.refresh(force: true)
        try await wait { host.problem != nil }
        XCTAssertTrue(host.problem?.contains("TS2322") == true, host.problem ?? "")
        XCTAssertEqual(host.page?.id, original.id)
        try saved.write(to: source, options: .atomic)
        await host.showLibrary()
        XCTAssertNil(host.current)
        await host.open(try XCTUnwrap(host.records.first))
        try await wait { host.page != nil || host.problem != nil }
        XCTAssertEqual(host.page?.product.revision, original.product.revision, host.problem ?? "")
        await host.showLibrary()
    }
}

import XCTest
@testable import VoidHost

@MainActor
final class RuntimeTests: XCTestCase {
    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RuntimeIssue("等待项目会话超时") }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    func testSwiftUIProjectOpensDirectlyAndDetectsEditsThatNeedANewBuild() async throws {
        let name = "SwiftUI-" + UUID().uuidString
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let project = FolderGrant.documents.appendingPathComponent(name)
        defer {
            try? FileManager.default.removeItem(at: storage)
            try? FileManager.default.removeItem(at: project)
        }
        let host = HostModel(storage: storage)
        await host.create(name, parent: nil)
        try await wait { host.screen != nil || host.problem != nil || host.notice != nil }
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
        host.open(try XCTUnwrap(host.records.first))
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

    func testBrokenEditKeepsNativePageAndProjectCanBeReopened() async throws {
        let name = "RuntimeTests-" + UUID().uuidString
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let project = FolderGrant.documents.appendingPathComponent(name)
        defer {
            try? FileManager.default.removeItem(at: storage)
            try? FileManager.default.removeItem(at: project)
        }
        let host = HostModel(storage: storage)
        await host.create(name, parent: nil, template: .tsx)
        try await wait { host.page != nil || host.problem != nil || host.notice != nil }
        let original = try XCTUnwrap(host.page, host.problem ?? host.notice ?? "")
        XCTAssertEqual(original.nodes.first?.type, "Form")
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
        host.open(try XCTUnwrap(host.records.first))
        try await wait { host.page != nil || host.problem != nil }
        XCTAssertEqual(host.page?.product.revision, original.product.revision, host.problem ?? "")
        await host.showLibrary()
    }
}

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

    func testBrokenEditKeepsNativePageAndProjectCanBeReopened() async throws {
        let name = "RuntimeTests-" + UUID().uuidString
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let project = FolderGrant.documents.appendingPathComponent(name)
        defer {
            try? FileManager.default.removeItem(at: storage)
            try? FileManager.default.removeItem(at: project)
        }
        let host = HostModel(storage: storage)
        await host.create(name, parent: nil)
        try await wait { host.page != nil || host.problem != nil || host.notice != nil }
        let original = try XCTUnwrap(host.page, host.problem ?? host.notice ?? "")
        XCTAssertEqual(original.nodes.first?.type, "Form")
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

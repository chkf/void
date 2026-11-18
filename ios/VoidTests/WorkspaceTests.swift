import XCTest
@testable import VoidHost

final class WorkspaceTests: XCTestCase {
    func testTemplateAndSharedDataBoundary() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }
        let url = try ProjectFiles.create("测试", in: parent)
        let first = try ProjectFiles.snapshot(at: url)
        XCTAssertEqual(first.info.mode, .swiftui)
        XCTAssertNoThrow(try CompiledProject.validate(first))
        XCTAssertEqual(first.info.name, "测试")
        XCTAssertNotNil(first.info.declaredID)
        for folder in ["app", "assets", "modules", "logs", "data"] {
            XCTAssertTrue(fm.fileExists(atPath: url.appendingPathComponent(folder).path))
        }
        for path in ["data/user.json", "logs/console.log"] {
            try Data("私有测试值".utf8).write(to: url.appendingPathComponent(path))
        }
        let second = try ProjectFiles.snapshot(at: url)
        XCTAssertEqual(first.revision, second.revision)
        XCTAssertNil(second.files["data/user.json"])
        XCTAssertThrowsError(try ProjectFiles.create("测试", in: parent))
        try ProjectFiles.rename("新名称", at: url)
        let renamed = try ProjectFiles.snapshot(at: url)
        XCTAssertNotEqual(first.revision, renamed.revision)
        XCTAssertEqual(first.info.declaredID, renamed.info.declaredID)
        XCTAssertEqual(renamed.info.name, "新名称")
        try fm.createSymbolicLink(at: url.appendingPathComponent("app/outside.json"), withDestinationURL: url.appendingPathComponent("data/user.json"))
        XCTAssertThrowsError(try ProjectFiles.snapshot(at: url))
    }

    func testHTMLCompatibilityAndBrokenManifest() throws {
        var files = ["app/index.html": Data("<main>页面</main>".utf8), "app/manifest.json": Data("{}".utf8)]
        XCTAssertEqual(try ProjectFiles.info(files, folderName: "旧项目").mode, .web)
        files["app/manifest.json"] = Data(#"{"entry":"../data/private.html"}"#.utf8)
        XCTAssertThrowsError(try ProjectFiles.info(files, folderName: "损坏"))
        files["app/manifest.json"] = Data("{".utf8)
        XCTAssertThrowsError(try ProjectFiles.info(files, folderName: "损坏"))
    }

    func testMediaRange() {
        XCTAssertEqual(ResourceServer.byteRange("bytes=1-3", count: 5), 1..<4)
        XCTAssertEqual(ResourceServer.byteRange("bytes=-2", count: 5), 3..<5)
        XCTAssertNil(ResourceServer.byteRange("bytes=8-", count: 5))
    }

    func testDiscoverRenameConflictsAndRepair() async throws {
        let fm = FileManager.default
        let parent = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        let registry = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent); try? fm.removeItem(at: registry) }
        let library = ProjectLibrary(base: registry)
        let a = try await library.create(name: "原生", parent: parent)
        let html = parent.appendingPathComponent("旧项目/app")
        try fm.createDirectory(at: html, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: html.appendingPathComponent("manifest.json"))
        try Data("<main>项目</main>".utf8).write(to: html.appendingPathComponent("index.html"))
        let discovered = try await library.discover(parent)
        XCTAssertEqual(discovered.count, 2)
        let b = try XCTUnwrap(discovered.first { $0.id != a.id })
        let old = try await library.open(b.id, remember: true)
        XCTAssertEqual(old.info.mode, .web)
        try await library.rename(a, name: "新名称")
        let reopened = try await library.open(a.id, remember: true)
        XCTAssertEqual(reopened.info.name, "新名称")
        let restored = try await ProjectLibrary(base: registry).catalog()
        XCTAssertEqual(restored.last, a.id)
        let clone = parent.appendingPathComponent("副本")
        try fm.copyItem(at: parent.appendingPathComponent("原生"), to: clone)
        do { _ = try await library.discover(clone); XCTFail("应拒绝副本的身份冲突") }
        catch { XCTAssertTrue(error.localizedDescription.contains("相同")) }
        let manifest = html.appendingPathComponent("manifest.json")
        try Data("{".utf8).write(to: manifest, options: .atomic)
        do { _ = try await library.open(b.id, remember: true); XCTFail("应报告损坏的清单") }
        catch { XCTAssertTrue(error.localizedDescription.contains("app/manifest.json")) }
        try Data("{}".utf8).write(to: manifest, options: .atomic)
        let repaired = try await library.open(b.id, remember: true)
        XCTAssertEqual(repaired.revision, old.revision)
    }

    func testRejectsInvalidNativeTree() throws {
        let data = Data(#"{"revision":1,"eventSequence":0,"nodes":[{"type":"Toggle","id":"a","props":{"label":"显示","value":"yes"},"children":[]}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(NativeCommit.self, from: data).validate())
    }
}

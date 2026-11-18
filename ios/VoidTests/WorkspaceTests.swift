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
        XCTAssertEqual(first.info.mode, .native)
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

    func testRejectsInvalidNativeTree() throws {
        let data = Data(#"{"revision":1,"eventSequence":0,"nodes":[{"type":"Toggle","id":"a","props":{"label":"显示","value":"yes"},"children":[]}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(NativeCommit.self, from: data).validate())
    }
}

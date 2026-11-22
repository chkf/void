import XCTest
@testable import VoidHost

final class WorkspaceTests: XCTestCase {
    func testAllProjectsMigratesOldVisibilityAndDiscardsOpenTimes() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let url = directory.appendingPathComponent("projects.json")
        let selected = UUID()
        func old(_ name: String, _ date: Int?, id: UUID = UUID()) -> [String: Any] {
            var fields: [String: Any] = ["id": id.uuidString, "name": name, "grant": ["child": name],
                                          "directoryKey": name, "version": "1"]
            if let date { fields["opened"] = date }
            return fields
        }
        let records = [old("Z", 900, id: selected), old("A", 1), old("Hidden", nil)]
        let data = try JSONSerialization.data(withJSONObject: ["records": records, "last": selected.uuidString])
        try data.write(to: url)
        let catalog = try await ProjectLibrary(base: directory).catalog()
        XCTAssertEqual(catalog.projects.map(\.name), ["A", "Z"])
        XCTAssertEqual(catalog.last, selected)
        XCTAssertEqual(catalog.records.count, 3)
        let saved = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.projects.map(\.id), catalog.projects.map(\.id))
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("\"opened\""))
    }

    func testGitHubImportAcceptsPublicRepositoryAddresses() throws {
        let repo = try GitHubRepository(" https://GitHub.com/owner/My-Project.git/ ")
        XCTAssertEqual(repo.address, "https://github.com/owner/My-Project.git")
        XCTAssertEqual(repo.name, "My-Project")
        XCTAssertEqual(repo, try GitHubRepository("https://github.com/owner/My-Project"))
        for invalid in ["https://example.com/o/r", "http://github.com/o/r", "https://token@github.com/o/r",
                        "https://github.com/o/r/tree/main", "https://github.com/O/%2F", "https://github.com/o/..",
                        "https://github.com:123/o/r", "https://github.com/o/r?k=v"] {
            XCTAssertThrowsError(try GitHubRepository(invalid), invalid)
        }
    }

    func testTemplateAndSharedDataBoundary() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }
        let url = try ProjectFiles.create("测试", in: parent)
        let first = try ProjectFiles.snapshot(at: url)
        XCTAssertEqual(first.info.mode, .native)
        XCTAssertEqual(first.info.entry, "src/main.tsx")
        XCTAssertNotNil(first.files["app/src/main.tsx"])
        XCTAssertNotNil(first.files["app/package.json"])
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
        try await library.rename(a.id, name: "新名称")
        let reopened = try await library.open(a.id, remember: true)
        XCTAssertEqual(reopened.info.name, "新名称")
        let restored = try await ProjectLibrary(base: registry).catalog()
        XCTAssertEqual(restored.last, a.id)
        let clone = parent.appendingPathComponent("副本")
        try fm.copyItem(at: parent.appendingPathComponent("新名称"), to: clone)
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
        let params = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertThrowsError(try NativeCommit(message:params))
        let row: [String:Any] = ["type":"Text","id":"a","props":["value":"one"],"children":[]]
        XCTAssertThrowsError(try NativeCommit(message:["revision":true,"eventSequence":0,"nodes":[]]))
        XCTAssertThrowsError(try NativeCommit(message:["revision":1,"eventSequence":0,"nodes":[row,row]]))
        XCTAssertThrowsError(try NativeCommit(message:["revision":1,"eventSequence":0,"nodes":Array(repeating:row,count:16_385)]))
        let valid = try NativeCommit(message:["revision":2,"eventSequence":1,"nodes":[row]])
        XCTAssertEqual(valid.nodes.first?.text("value"),"one")
    }

    func testBuildStoreWritesRawResourcesAndCanRestoreLegacyVersion() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let id = UUID(), folder = base.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:base) }
        let store = ProductStore(base:base)
        let old = Product(entry:"index.html",files:["index.html":Data("older".utf8)],mode:.web,revision:"a")
        let oldKey = "a-previous-toolchain"
        let legacy = folder.appendingPathComponent(oldKey + ".json")
        let oldBytes = try JSONEncoder().encode(old)
        try oldBytes.write(to:legacy)
        let history = folder.appendingPathComponent("history.json")
        try JSONEncoder().encode(BuildHistory(current:oldKey)).write(to:history)
        let asset = Data(repeating:17,count:2 * 1024 * 1024)
        let next = Product(entry:"index.html",files:["index.html":Data("new".utf8),"assets/图 片.bin":asset],mode:.web,revision:"b")
        try await store.confirm(next,project:id)
        let pointer = try JSONDecoder().decode(BuildHistory.self,from:Data(contentsOf:history))
        XCTAssertEqual(pointer.previous,oldKey)
        let directory = folder.appendingPathComponent(try XCTUnwrap(pointer.current) + ".product")
        XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("0")),asset)
        let reopened = try await store.matching("b",project:id)
        XCTAssertEqual(reopened?.files,next.files)
        let prior = try await store.accepted(id,previous:true)
        try await store.confirm(try XCTUnwrap(prior),project:id)
        let restored = try JSONDecoder().decode(BuildHistory.self,from:Data(contentsOf:history))
        XCTAssertEqual(restored.current,oldKey)
        let cancelled = DirectoryCommit()
        XCTAssertTrue(cancelled.cancel())
        do { try await store.confirm(next,project:id,commit:cancelled); XCTFail("中断页不能取代原可运行版本") }
        catch is CancellationError { }
        XCTAssertEqual(try JSONDecoder().decode(BuildHistory.self,from:Data(contentsOf:history)).current,oldKey)
        XCTAssertEqual(try Data(contentsOf:legacy),oldBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath:directory.path))
    }

    func testRemovingHistoryPreservesFilesAndProjectIdentity() async throws {
        let manager = FileManager.default
        let parent = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        let registry = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: parent); try? manager.removeItem(at: registry) }
        let library = ProjectLibrary(base: registry)
        let a = try await library.create(name: "笔记", parent: parent)
        let b = try await library.create(name: "日程", parent: parent)
        let path = parent.appendingPathComponent("笔记/data/saved.txt")
        try Data("保留".utf8).write(to: path)
        _ = try await library.open(a.id, remember: true)
        try await library.removeFromList(a.id)
        let saved = try await ProjectLibrary(base: registry).catalog()
        XCTAssertEqual(saved.projects.map(\.id), [b.id])
        XCTAssertNil(saved.last)
        XCTAssertEqual(try Data(contentsOf: path), Data("保留".utf8))
        let restored = try await library.discover(parent.appendingPathComponent("笔记"))
        XCTAssertEqual(restored.first?.id, a.id)
        XCTAssertEqual(restored.first?.pendingTemplate, .tsx)
        let reopened = try await library.catalog()
        XCTAssertEqual(reopened.projects.count, 2)
    }
}

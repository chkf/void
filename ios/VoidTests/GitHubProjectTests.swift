import XCTest
@testable import VoidHost

final class GitHubProjectTests: XCTestCase {
    func testClonePullValidateAndRecoverTheSameProject() async throws {
        let manager = FileManager.default
        let temp = manager.temporaryDirectory
        guard let fixture = ProcessInfo.processInfo.environment["VOID_GIT_FIXTURE"] else {
            throw XCTSkip("scripts/ios-build.sh run-tests 准备离线 Git 仓库")
        }
        let store = temp.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: store, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: store) }
        let remote = store.appendingPathComponent("origin")
        try manager.copyItem(at: temp.appendingPathComponent(fixture), to: remote)
        let refs = remote.appendingPathComponent(".git/refs/heads")
        func advance(to name: String) throws {
            try Data(contentsOf: refs.appendingPathComponent(name)).write(to: refs.appendingPathComponent("main"), options: .atomic)
        }
        let source = try GitHubRepository("https://github.com/example/Void-" + UUID().uuidString)
        let project = FolderGrant.documents.appendingPathComponent(source.name)
        defer { try? manager.removeItem(at: project) }
        let library = ProjectLibrary(base: store)
        let initial = try await library.clone(source) { _, destination in try ProjectGit.clone(remote.absoluteString, to: destination) }
        XCTAssertEqual(initial.github?.address, source.address)
        XCTAssertEqual(initial.version, "1.0.0")
        XCTAssertFalse(manager.fileExists(atPath: project.appendingPathComponent(".git").path))
        let note = project.appendingPathComponent("note.txt")
        try Data("本地笔记".utf8).write(to: note)
        let before = try await library.catalog()
        try advance(to: "update")
        let updated = try await library.pull(initial.id)
        XCTAssertEqual(updated.id, initial.id)
        XCTAssertEqual(updated.version, "2.0.0")
        XCTAssertNotEqual(updated.github?.commit, initial.github?.commit)
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "本地笔记")

        // Simulate termination after exchanging directories and before the final catalog write.
        var interrupted = before
        interrupted.pendingInstall = updated
        try JSONEncoder().encode(interrupted).write(to: store.appendingPathComponent("projects.json"), options: .atomic)
        let reopened = ProjectLibrary(base: store)
        let recovered = try await reopened.catalog()
        XCTAssertNil(recovered.pendingInstall)
        XCTAssertEqual(recovered.projects.first?.github?.commit, updated.github?.commit)
        let preview = try await reopened.open(initial.id, remember: true)
        XCTAssertEqual(preview.info.version, "2.0.0")
        XCTAssertNotNil(preview.files["app/src/main.tsx"])

        try advance(to: "invalid")
        do { _ = try await reopened.pull(initial.id); XCTFail("应拒绝无效清单") }
        catch { XCTAssertTrue(error.localizedDescription.contains("manifest.json"), error.localizedDescription) }
        let intact = try await reopened.details(initial.id)
        XCTAssertEqual(intact.version, "2.0.0")
        XCTAssertEqual(intact.github?.commit, updated.github?.commit)
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "本地笔记")
    }
}

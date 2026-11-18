import XCTest
@testable import VoidHost

@MainActor
final class PreviewRecoveryTests: XCTestCase {
    func testInterruptedPreviewReturnsToLibraryAndManuallyOpensOriginal() async throws {
        let name = "Preview-" + UUID().uuidString
        let root = FolderGrant.documents.appendingPathComponent(name)
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at:storage); try? FileManager.default.removeItem(at:root) }
        let library = ProjectLibrary(base:storage)
        _ = try ProjectFiles.create(name,in:FolderGrant.documents,template:.tsx)
        let found = try await library.discover(root)
        let original = try XCTUnwrap(found.first)
        _ = try await library.open(original.id,remember:true)
        let recovery = PreviewRecovery(storage:storage)
        let former = UUID(), active = UUID()
        try await recovery.mark(PreviewAttempt(request:former,project:original.id,stage:.compiler),starting:true)
        try await recovery.mark(PreviewAttempt(request:active,project:original.id,stage:.compile),starting:true)
        try await recovery.finish(former)
        let host = HostModel(storage:storage)
        await host.load()
        XCTAssertNil(host.current)
        XCTAssertEqual(host.records.map(\.id),[original.id])
        XCTAssertTrue(host.notice?.contains("正在编译项目") == true)
        let pending = try await recovery.pending()
        XCTAssertEqual(pending?.request,active)
        host.notice = nil
        await host.open(original)
        let end = ContinuousClock.now + .seconds(115)
        while host.busy && ContinuousClock.now < end { try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertNotNil(host.page,host.problem ?? "")
        XCTAssertEqual(host.current?.id,original.id)
        let finished = try await recovery.pending()
        XCTAssertNil(finished)
        await host.showLibrary()
    }

    func testCompilerTimeoutAndCancellationReleaseARealWebKitWait() async throws {
        let resources = [
            "index.html":Data("<script src='compiler-client.js'></script>".utf8),
            "compiler-client.js":try Toolchain.read("compiler-client.js"),
            "compiler.js":Data("self.onmessage = e => setTimeout(() => self.postMessage({entry:'done'}), e.data.delay)".utf8)
        ]
        let server = try ResourceServer(files:resources,compiler:true)
        defer { server.stop() }
        let url = try await server.start().appendingPathComponent("index.html")
        let slow = CompilerPage()
        try await slow.load(url)
        do {
            _ = try await slow.compile(["delay":30000],timeout:.milliseconds(100))
            XCTFail("应结束首个等待")
        } catch { XCTAssertTrue(error.localizedDescription.contains("编译项目超时"),error.localizedDescription) }
        slow.stop()

        let cancelled = CompilerPage()
        try await cancelled.load(url)
        let waiting = Task { try await cancelled.compile(["delay":30000]) }
        await Task.yield()
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("取消后不能提交结果") }
        catch { XCTAssertTrue(error is CancellationError) }
        cancelled.stop()

        let next = CompilerPage()
        defer { next.stop() }
        try await next.load(url)
        let output = try await next.compile(["delay":0])
        XCTAssertEqual(output["entry"] as? String,"done")
    }
}

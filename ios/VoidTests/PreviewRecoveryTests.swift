import XCTest
@testable import VoidHost

@MainActor
final class PreviewRecoveryTests: XCTestCase {
    func testRecoveryUsesTheInterruptedRequestEvenAfterNewerFolderScan() {
        let preview = DirectoryTrace("preview"), folder = DirectoryTrace("import")
        let attempt = PreviewAttempt(request:preview.id,project:UUID(),stage:.firstFrame)
        preview.event("preview.firstFrame")
        preview.event("page.navigationFinished")
        folder.event("page.contentReady")
        folder.event("import.result","OK")
        XCTAssertEqual(PreviewRecovery.interruptionTitle(attempt,entries:DirectoryJournal.shared.recent()),"网页已载入，等待项目提交首屏")
        preview.event("page.nativeCommitReceived")
        XCTAssertEqual(PreviewRecovery.interruptionTitle(attempt,entries:DirectoryJournal.shared.recent()),"正在处理项目提交的原生控件")
        let verifying = PreviewAttempt(request:preview.id,project:attempt.project,stage:.verifyPage)
        preview.event("sdk.consent.begin","database")
        folder.event("sdk.consent.end","database 允许")
        XCTAssertEqual(PreviewRecovery.interruptionTitle(verifying,entries:DirectoryJournal.shared.recent()),"正在等待项目权限选择（database）")
        preview.event("sdk.consent.end","database 允许")
        XCTAssertEqual(PreviewRecovery.interruptionTitle(verifying,entries:DirectoryJournal.shared.recent()),verifying.stage.title)
    }

    func testUpgradeRecognizesIncompleteDev4PreviewOnly() {
        let trace = DirectoryTrace("preview"), other = DirectoryTrace("preview")
        trace.event("preview.begin"); trace.event("scan.end"); other.event("preview.result")
        func events() -> [DirectoryEvent] { DirectoryJournal.shared.recent().filter { $0.request == trace.id || $0.request == other.id } }
        XCTAssertEqual(PreviewRecovery.interruptedLegacyRequest(events()),trace.id)
        trace.event("preview.result","OK")
        XCTAssertNil(PreviewRecovery.interruptedLegacyRequest(events()))
        other.event("preview.begin"); other.event("preview.cancel")
        XCTAssertNil(PreviewRecovery.interruptedLegacyRequest(events()))
    }

    func testInterruptedPreviewReturnsToLibraryAndManuallyOpensOriginal() async throws {
        let name = "Preview-" + UUID().uuidString
        let root = FolderGrant.documents.appendingPathComponent(name)
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at:storage); try? FileManager.default.removeItem(at:root) }
        let library = ProjectLibrary(base:storage)
        _ = try ProjectFiles.create(name,in:FolderGrant.documents)
        let found = try await library.discover(root)
        let original = try XCTUnwrap(found.first)
        // An interruption can occur on the very first scan, before the last-opened
        // catalog pointer has been written.
        let before = try await library.catalog()
        XCTAssertNil(before.last)
        let recovery = PreviewRecovery(storage:storage)
        let former = UUID(), active = UUID()
        try await recovery.mark(PreviewAttempt(request:former,project:original.id,stage:.compiler),starting:true)
        try await recovery.mark(PreviewAttempt(request:active,project:original.id,stage:.compile),starting:true)
        try await recovery.finish(former)
        let host = HostModel(storage:storage)
        await host.load()
        XCTAssertNil(host.current)
        XCTAssertEqual(host.records.map(\.id),[original.id])
        XCTAssertTrue(host.recoveryMessage?.contains("正在编译项目") == true)
        let diagnostic = DirectoryJournal().recent().last { $0.request == active }
        XCTAssertEqual(diagnostic?.stage, "preview.interrupted")
        XCTAssertEqual(diagnostic?.detail, PreviewStage.compile.rawValue)
        let pending = try await recovery.pending()
        XCTAssertEqual(pending?.request,active)
        let window = try await PreviewTestWindow(host)
        defer { window.close() }
        await host.open(original)
        let end = ContinuousClock.now + .seconds(115)
        while host.busy && ContinuousClock.now < end { try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertNotNil(host.page,host.problem ?? "")
        XCTAssertEqual(host.current?.id,original.id)
        let finished = try await recovery.pending()
        XCTAssertNil(finished)
        await host.showLibrary()
    }

    func testNewWorkspaceRemainsSelectedAfterADifferentInterruptedPreview() async throws {
        let prefix = "恢复-" + UUID().uuidString
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(prefix)
        let firstName = prefix + "-A", nextName = prefix + "-B"
        defer {
            for name in [firstName,nextName] { try? FileManager.default.removeItem(at:FolderGrant.documents.appendingPathComponent(name)) }
            try? FileManager.default.removeItem(at:storage)
        }
        let library = ProjectLibrary(base:storage)
        let first = try await library.create(name:firstName,parent:nil)
        let recovery = PreviewRecovery(storage:storage)
        try await recovery.mark(PreviewAttempt(request:UUID(),project:first.id,stage:.firstFrame),starting:true)
        let host = HostModel(storage:storage)
        await host.load()
        XCTAssertNil(host.current)
        XCTAssertNotNil(host.recoveryMessage)
        await host.create(nextName,parent:nil)
        let next = try XCTUnwrap(host.current)
        let catalog = try await library.catalog()
        XCTAssertEqual(catalog.last,next.id)
        XCTAssertEqual(Set(catalog.records.map(\.id)),[first.id,next.id])
        let acknowledged = try await recovery.pending()
        XCTAssertNil(acknowledged)
        let relaunched = HostModel(storage:storage)
        await relaunched.load()
        XCTAssertEqual(relaunched.current?.id,next.id)
        XCTAssertEqual(relaunched.workspaceTemplate,.tsx)
        XCTAssertNil(relaunched.recoveryMessage)
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

        var pages = [CompilerPage]()
        let next = try await CompilerPage.start(url,firstTimeout:.zero) { pages.append($0) }
        defer { next.stop() }
        XCTAssertEqual(pages.count,2,"首次启动超时应仅重试一次")
        XCTAssertFalse(pages.first === next)
        XCTAssertTrue(pages.last === next)
        let output = try await next.compile(["delay":0])
        XCTAssertEqual(output["entry"] as? String,"done")
    }
}

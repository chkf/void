import XCTest
@testable import VoidHost

final class FolderRequestTests: XCTestCase {
    @MainActor
    func testPresentationSelectionDismissalAndStaleRequestDelivery() async throws {
        let flow = FolderRequests(), project = UUID()
        var calls: [UUID] = []
        flow.process = { request,_ in calls.append(request.id); return "已打开" }
        let create = flow.begin(.create("文件夹",.tsx),origin:nil,afterSheet:true)
        XCTAssertFalse(flow.ready)
        flow.sheetClosed(); XCTAssertTrue(flow.ready)
        flow.didPresent(create.id); flow.cancel(create.id); flow.dismissed(create.id)
        flow.picked(create.id,[FolderGrant.documents]); XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(flow.phase,.cancelled)

        let empty = flow.begin(.importFolder,origin:nil)
        flow.didPresent(empty.id); flow.picked(empty.id,[]); flow.dismissed(empty.id)
        XCTAssertEqual(flow.phase,.failed); XCTAssertTrue(calls.isEmpty)
        let selected = flow.begin(.reconnect(project),origin:project,afterSheet:true)
        flow.sheetClosed(); flow.didPresent(selected.id)
        flow.picked(empty.id,[FolderGrant.documents]); XCTAssertEqual(flow.phase,.presenting)
        flow.picked(selected.id,[FolderGrant.documents]); flow.picked(selected.id,[])
        XCTAssertEqual(flow.phase,.selected); XCTAssertTrue(calls.isEmpty)
        flow.dismissed(selected.id); flow.dismissed(selected.id)
        for _ in 0..<100 where flow.active { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertEqual(calls,[selected.id]); XCTAssertEqual(flow.phase,.succeeded)
        let stages = DirectoryJournal.shared.recent().filter{$0.request == selected.id}.map(\.stage)
        XCTAssertEqual(stages.filter{$0=="picker.didPick"}.count,1)
        XCTAssertEqual(stages.filter{$0=="picker.dismiss"}.count,1)
        XCTAssertEqual(stages.filter{$0=="reconnect.result"}.count,1)

        let stale = flow.begin(.reconnect(project),origin:project)
        flow.didPresent(stale.id); flow.picked(stale.id,[FolderGrant.documents])
        flow.changeProject(to:UUID()); flow.dismissed(stale.id)
        XCTAssertEqual(flow.phase,.cancelled); XCTAssertEqual(calls,[selected.id])
        let swipe = flow.begin(.importFolder,origin:nil)
        flow.didPresent(swipe.id); flow.dismissed(swipe.id)
        XCTAssertEqual(flow.phase,.cancelled)
        XCTAssertEqual(DirectoryJournal.shared.recent().last{$0.request == swipe.id && $0.stage == "picker.dismiss"}?.detail,"未收到选择回调")
    }

    @MainActor
    func testCancelProcessingAndSwitchDoesNotChangeGrant() async throws {
        let flow = FolderRequests(), origin = UUID()
        var completions = 0, began = false
        flow.process = { r,_ in
            began = true
            try await Task.sleep(for:.seconds(3))
            try r.commit.begin()
            completions += 1
            return "已登记"
        }
        let r = flow.begin(.reconnect(origin),origin:origin)
        flow.didPresent(r.id); flow.picked(r.id,[FolderGrant.documents]); flow.dismissed(r.id)
        for _ in 0..<100 where !began { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertTrue(began)
        flow.changeProject(to:UUID())
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertEqual(completions,0); XCTAssertEqual(flow.phase,.cancelled)
        XCTAssertThrowsError(try r.commit.begin())
    }

    @MainActor
    func testProjectSwitchAfterCommitWaitsForActualSaveResult() async throws {
        let flow = FolderRequests(), project = UUID()
        var finishWrite: CheckedContinuation<Void,Never>?
        flow.process = { request,_ in
            try request.commit.begin()
            await withCheckedContinuation { finishWrite = $0 }
            throw DirectoryIssue(kind:.unreadable,item:"登记目录")
        }
        let request = flow.begin(.reconnect(project),origin:project)
        flow.picked(request.id,[FolderGrant.documents]); flow.dismissed(request.id)
        for _ in 0..<100 where finishWrite == nil { try await Task.sleep(for:.milliseconds(10)) }
        let finish = try XCTUnwrap(finishWrite)
        flow.changeProject(to:UUID())
        XCTAssertEqual(flow.phase,.processing)
        finish.resume()
        for _ in 0..<100 where flow.active { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertEqual(flow.phase,.failed)
        let results = DirectoryJournal.shared.recent().filter { $0.request == request.id && $0.stage == "reconnect.result" }
        XCTAssertEqual(results.count,1)
        XCTAssertEqual(results.first?.code,DirectoryIssue.Kind.unreadable.rawValue)
    }

    func testBlockedFileCoordinatorIsCancelledAndLateAccessorCannotRun() async throws {
        let dir = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let grant = try FolderGrant.selected(dir)
        let writerStarted = expectation(description:"排他写入协调已开始")
        let writerDone = expectation(description:"排他写入协调已退出")
        let attempted = expectation(description:"已开始读取")
        let late = expectation(description:"被取消的读取不能执行"); late.isInverted = true
        let release = DispatchSemaphore(value:0)
        DispatchQueue.global().async {
            let writer = NSFileCoordinator()
            var error: NSError?
            writer.coordinate(writingItemAt:dir,options:.forReplacing,error:&error) { _ in
                writerStarted.fulfill()
                _ = release.wait(timeout:.now()+6)
            }
            writerDone.fulfill()
        }
        await fulfillment(of:[writerStarted],timeout:3)
        let start = ContinuousClock.now
        do {
            _ = try await DirectoryIO.run(timeout:0.4) { io in
                attempted.fulfill()
                return try grant.coordinated(io:io) { _ in late.fulfill(); return 1 }
            }
            XCTFail("等待协调应返回超时")
        } catch { XCTAssertEqual((error as? DirectoryIssue)?.kind,.timeout) }
        XCTAssertLessThan(start.duration(to:.now),.seconds(3))
        release.signal()
        await fulfillment(of:[attempted,writerDone],timeout:3)
        await fulfillment(of:[late],timeout:0.3)
    }

    func testUserCancellationDuringReadDropsLateCompletion() async throws {
        let entered = expectation(description:"已进入读取器")
        let done = expectation(description:"读取器退出")
        let resume = DispatchSemaphore(value:0)
        let task = Task {
            try await DirectoryIO.run { io in
                entered.fulfill(); defer { done.fulfill() }
                _ = resume.wait(timeout:.now()+5)
                try io.check()
                return 42
            }
        }
        await fulfillment(of:[entered],timeout:2)
        task.cancel()
        do { _ = try await task.value; XCTFail("不能发布晚到的结果") } catch { XCTAssertTrue(error is CancellationError) }
        resume.signal()
        await fulfillment(of:[done],timeout:2)
    }
}

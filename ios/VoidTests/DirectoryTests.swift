import Darwin
import SwiftUI
import XCTest
@testable import VoidHost

final class DirectoryTests: XCTestCase {
    private let fm = FileManager.default
    private var parent: URL!
    private var root: URL!
    private var store: URL!
    private let declared = UUID().uuidString
    private let manifest = #"{"name":"目录测试","uiMode":"native","entry":"src/main.tsx","version":"1.1.0","permissions":["database"]}"#
    private let main = #"import {render,Text} from "@runtime/ui"; import {title} from "./detail"; render(<Text value={title}/>);"#
    override func setUpWithError() throws {
        parent = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        root = parent.appendingPathComponent("中文 项目",isDirectory:true)
        store = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root.appendingPathComponent("app/src"),withIntermediateDirectories:true)
        try write(manifest,"app/manifest.json")
        try write(main,"app/src/main.tsx")
        try write("export const title = '首次预览';","app/src/detail.ts")
        try write(#"{"dependencies":{"@runtime/ui":"1.0.0","react":"18.3.1"}}"#,"app/package.json")
        try write("{\"formatVersion\":1,\"id\":\"\(declared)\"}","runtime.json")
    }
    override func tearDownWithError() throws {
        if let parent { try? fm.removeItem(at:parent) }
        if let store { try? fm.removeItem(at:store) }
    }
    private func write(_ text: String,_ path: String) throws {
        try Data(text.utf8).write(to:root.appendingPathComponent(path),options:.atomic)
    }
    private func atomicEditorSave(_ text: String,_ path: String) throws {
        let target = root.appendingPathComponent(path)
        let temp = target.deletingLastPathComponent().appendingPathComponent(".editor-" + UUID().uuidString)
        try Data(text.utf8).write(to:temp)
        XCTAssertEqual(chflags(temp.path,UInt32(UF_HIDDEN)),0)
        XCTAssertEqual(Darwin.rename(temp.path,target.path),0)
    }
    func testRealScanAfterAtomicEditorSaveAndDirectoryAliases() async throws {
        let library = ProjectLibrary(base:store)
        let initial = try await library.discover(root)
        let record = try XCTUnwrap(initial.first)
        let first = try await library.open(record.id,remember:true)
        XCTAssertEqual(first.info.runtimeID,declared)
        XCTAssertEqual(first.files["app/src/main.tsx"],Data(main.utf8))
        for path in ["data","logs"] {
            let dir = root.appendingPathComponent(path)
            try fm.createDirectory(at:dir,withIntermediateDirectories:true)
            try Data("private sentinel".utf8).write(to:dir.appendingPathComponent("private.txt"))
        }
        try atomicEditorSave(manifest + "\n","app/manifest.json")
        try atomicEditorSave(main + "\n","app/src/main.tsx")
        try atomicEditorSave("export const title = '保存后';","app/src/detail.ts")
        try write("unfinished","app/src/.editor-pending")
        // Exercise the FileManager flags used by dev.3 on the very same directory.
        let legacy = try XCTUnwrap(fm.enumerator(at:root.appendingPathComponent("app"),includingPropertiesForKeys:[.isRegularFileKey],
                                                options:[.skipsHiddenFiles]))
        let names = legacy.compactMap { ($0 as? URL)?.lastPathComponent }
        XCTAssertFalse(names.contains("manifest.json"),"旧版枚举应漏掉带 UF_HIDDEN 的清单")
        let aliases = [root.path,root.path + "/",root.path.hasPrefix("/private/var/") ? String(root.path.dropFirst(8)) :
            (root.path.hasPrefix("/var/") ? "/private" + root.path : root.path)]
        for path in aliases {
            let url = URL(fileURLWithPath:path,isDirectory:true)
            let snapshot = try ProjectFiles.snapshot(at:url)
            XCTAssertNotEqual(first.revision,snapshot.revision)
            XCTAssertEqual(Set(snapshot.files.keys),Set(["app/manifest.json","app/src/main.tsx","app/src/detail.ts","app/package.json","runtime.json"]))
            try await library.reconnect(record.id,url:url)
            let records = try await library.discover(url)
            XCTAssertEqual(records.map(\.id),[record.id])
        }
    }

    func testDirectFilesSurviveProviderListingOmissionAndUnknownType() throws {
        let ordinary = ProjectSourceReader(), trace = DirectoryTrace("scan-test")
        var reader = ordinary
        reader.metadata = { _ in ProjectSourceReader.Traits() }
        reader.children = { url in
            try ordinary.children(url).filter { !["manifest.json","main.tsx"].contains($0.lastPathComponent) }
        }
        let snapshot = try reader.snapshot(root,allowMissingEntry:false,trace:trace,io:nil)
        XCTAssertEqual(snapshot.files["app/manifest.json"],Data(manifest.utf8))
        XCTAssertEqual(snapshot.files["app/src/main.tsx"],Data(main.utf8))
        let events = DirectoryJournal.shared.recent().filter{$0.request == trace.id}
        XCTAssertEqual(Set(events.filter{$0.stage == "scan.enumerationOmitted"}.map(\.detail)),["manifest","entry"])
        XCTAssertTrue(events.allSatisfy{!$0.line.contains(root.path)})
        reader.children = { _ in [self.parent.appendingPathComponent("outside")] }
        XCTAssertThrowsError(try reader.snapshot(root,allowMissingEntry:false,trace:nil,io:nil)) {
            XCTAssertEqual(($0 as? DirectoryIssue)?.kind,.outside)
        }
    }

    func testFingerprintMatchesFullContentsWithoutRetainingAssetsAndBoundsGrowingSources() throws {
        let asset = root.appendingPathComponent("assets/图 像.bin")
        try fm.createDirectory(at:asset.deletingLastPathComponent(),withIntermediateDirectories:true)
        let content = Data(repeating:91,count:2 * 1024 * 1024 + 7)
        try content.write(to:asset)
        var reader = ProjectSourceReader()
        let full = try reader.snapshot(root,allowMissingEntry:false,trace:nil,io:nil)
        let check = try reader.snapshot(root,allowMissingEntry:false,trace:nil,io:nil,retainingSources:false)
        XCTAssertEqual(full.files["assets/图 像.bin"],content)
        XCTAssertEqual(full.revision,ProjectFiles.snapshot(info:full.info,files:full.files).revision)
        XCTAssertEqual(check.revision,full.revision)
        XCTAssertEqual(Set(check.files.keys),["app/manifest.json","runtime.json"])
        reader.sourceByteLimit = content.count - 1
        XCTAssertThrowsError(try reader.snapshot(root,allowMissingEntry:false,trace:nil,io:nil)) {
            XCTAssertEqual(($0 as? DirectoryIssue)?.kind,.sourceLimit)
        }
        XCTAssertEqual(try Data(contentsOf:asset),content)
    }

    @MainActor
    func testLocalScanAndRecentSelectionDoNotReadOrStartAProject() async throws {
        let name = "目录-" + UUID().uuidString
        let local = FolderGrant.documents.appendingPathComponent(name)
        try fm.copyItem(at:root,to:local)
        defer { try? fm.removeItem(at:local) }
        let library = ProjectLibrary(base:store)
        let original = try await library.discover(local)
        let record = try XCTUnwrap(original.first)
        let unavailable = local.appendingPathComponent("app/src/暂不可读.ts")
        try fm.createSymbolicLink(at:unavailable,withDestinationURL:local.appendingPathComponent("runtime.json"))
        let trace = DirectoryTrace("local-test")
        let found = try await library.discover(FolderGrant.documents,localRoot:true,trace:trace)
        XCTAssertTrue(found.contains { $0.id == record.id })
        let events = DirectoryJournal.shared.recent().filter { $0.request == trace.id }.map(\.stage)
        XCTAssertTrue(events.contains("scan.configuration"))
        XCTAssertFalse(events.contains("scan.sources"))
        let host = HostModel(storage:store)
        let scan = host.folders.begin(.local,origin:nil)
        let scanLimit = ContinuousClock.now + .seconds(25)
        while host.folders.active && ContinuousClock.now < scanLimit { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertEqual(host.folders.phase,.succeeded,host.folders.message)
        XCTAssertTrue(host.records.contains { $0.id == record.id })
        XCTAssertNil(host.current)
        XCTAssertFalse(host.busy)
        XCTAssertFalse(DirectoryJournal.shared.recent().contains { $0.request == scan.id && $0.stage == "preview.begin" })
        await host.selectRecent(record)
        XCTAssertTrue(host.showingOverview)
        XCTAssertFalse(host.shouldMonitor)
        XCTAssertFalse(host.busy)
        XCTAssertNil(host.compiler)
        XCTAssertNil(host.page)
        // Even the ordinary foreground watcher cannot start a preview from this screen.
        host.refresh()
        XCTAssertFalse(host.busy)
        host.refresh(force:true,remember:true)
        let deadline = ContinuousClock.now + .seconds(25)
        while host.busy && ContinuousClock.now < deadline { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertTrue(host.problem?.contains("符号链接") == true,host.problem ?? "")
        XCTAssertTrue(host.showingOverview)
        XCTAssertEqual(host.current?.id,record.id)
        XCTAssertTrue(fm.fileExists(atPath:unavailable.path))
    }

    func testFirstEmptyProviderListingRetriesOnceAndKeepsRelativeImports() throws {
        let ordinary = ProjectSourceReader(), trace = DirectoryTrace("scan-test")
        var reader = ordinary
        var counts = [String:Int]()
        reader.children = { directory in
            let name = directory.lastPathComponent
            counts[name,default:0] += 1
            if counts[name] == 1 { return [] }
            return try ordinary.children(directory)
        }
        let snapshot = try reader.snapshot(root,allowMissingEntry:false,trace:trace,io:nil)
        XCTAssertEqual(counts,["app":2,"src":2])
        XCTAssertEqual(snapshot.files["app/src/detail.ts"],Data("export const title = '首次预览';".utf8))
        XCTAssertEqual(DirectoryJournal.shared.recent().filter { $0.request == trace.id && $0.stage == "scan.retryEmpty" }.count,2)
    }

    func testRequiredFileDiagnosticsAndRegistrationAreNonDestructive() async throws {
        let url = root.appendingPathComponent("app/manifest.json"), library = ProjectLibrary(base:store)
        try fm.removeItem(at:url)
        do { _ = try await library.discover(root); XCTFail("应报告缺少清单") }
        catch { XCTAssertEqual((error as? DirectoryIssue)?.kind,.missing) }
        XCTAssertFalse(fm.fileExists(atPath:url.path))
        try write("{","app/manifest.json")
        do { _ = try await library.discover(root); XCTFail("不能登记坏清单") }
        catch { XCTAssertEqual((error as? DirectoryIssue)?.kind,.invalidJSON); XCTAssertNotNil((error as? DirectoryIssue)?.underlying) }
        XCTAssertEqual(try Data(contentsOf:url),Data("{".utf8))
        let empty = try await library.catalog(); XCTAssertTrue(empty.records.isEmpty)
        try write(manifest,"app/manifest.json")
        XCTAssertEqual(chmod(url.path,0o444),0)
        XCTAssertEqual(try ProjectFiles.snapshot(at:root).info.runtimeID,declared)
        if geteuid() != 0 {
            XCTAssertEqual(chmod(url.path,0),0)
            XCTAssertThrowsError(try ProjectFiles.snapshot(at:root)) { XCTAssertEqual(($0 as? DirectoryIssue)?.kind,.unreadable) }
        }
        XCTAssertEqual(chmod(url.path,0o600),0)
        let ordinary = ProjectSourceReader()
        var pending = ordinary
        pending.metadata = { item in
            if item.lastPathComponent == "manifest.json" { return ProjectSourceReader.Traits(pendingDownload:true) }
            return try ordinary.metadata(item)
        }
        XCTAssertThrowsError(try pending.snapshot(root,allowMissingEntry:false,trace:nil,io:nil)) { XCTAssertEqual(($0 as? DirectoryIssue)?.kind,.pendingDownload) }
        var unavailable = ordinary
        unavailable.bytes = { _ in throw NSError(domain:"NSFileProviderErrorDomain",code:-1004) }
        XCTAssertThrowsError(try unavailable.snapshot(root,allowMissingEntry:false,trace:nil,io:nil)) {
            XCTAssertEqual(($0 as? DirectoryIssue)?.kind,.provider)
            XCTAssertEqual(($0 as? DirectoryIssue)?.underlying?.code,-1004)
        }
        try fm.removeItem(at:url)
        try fm.createSymbolicLink(at:url,withDestinationURL:root.appendingPathComponent("runtime.json"))
        XCTAssertThrowsError(try ProjectFiles.snapshot(at:root)) { XCTAssertEqual(($0 as? DirectoryIssue)?.kind,.link) }
        XCTAssertTrue((try url.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink == true)
    }

    @MainActor
    func testUpdatingOriginalDirectoryKeepsCatalogDatabasePermissionsAndBuilds() async throws {
        let library = ProjectLibrary(base:store)
        let imported = try await library.discover(root)
        let original = try XCTUnwrap(imported.first)
        SDKConsent.shared.set(true,for:"database",project:original.id)
        defer { SDKConsent.shared.set(nil,for:"database",project:original.id) }
        func sql(_ record: ProjectRecord, _ method: String, _ text: String) async throws -> Any {
            let session = SDKSession(record:record,storage:store,permissions:["database"],networkHosts:[])
            defer { session.close() }
            let value: [String:Any] = await withCheckedContinuation { continuation in
                session.start(id:UUID().uuidString,method:"graphics." + method,params:["sql":text]) { reply,_ in
                    continuation.resume(returning:(reply as? [String:Any])?["result"] as? [String:Any] ?? [:])
                }
            }
            guard value["success"] as? Bool == true, let data = value["data"] else { throw RuntimeIssue("SQLite 操作未成功") }
            return data
        }
        _ = try await sql(original,"execute","CREATE TABLE saved(v INTEGER)")
        _ = try await sql(original,"execute","INSERT INTO saved VALUES(37)")
        let builds = store.appendingPathComponent("Builds/" + original.id.uuidString)
        try fm.createDirectory(at:builds,withIntermediateDirectories:true)
        let history = builds.appendingPathComponent("retained")
        try Data([1,2,3]).write(to:history)
        let catalogFile = store.appendingPathComponent("projects.json")
        var previous = try await library.catalog()
        previous.records[0].directoryKey = "previous-volume/inode"
        previous.last = original.id
        try JSONEncoder().encode(previous).write(to:catalogFile,options:.atomic)
        let cold = ProjectLibrary(base:store)
        _ = try await cold.open(original.id,remember:true)
        try await cold.reconnect(original.id,url:root)
        let restored = try await cold.discover(root)
        let same = try XCTUnwrap(restored.first)
        XCTAssertEqual(same.id,original.id); XCTAssertEqual(same.declaredID,declared)
        XCTAssertEqual(same.directoryKey,original.directoryKey)
        XCTAssertEqual(SDKConsent.shared.decision("database",project:same.id),true)
        let rows = try await sql(same,"query","SELECT CAST(v AS TEXT) AS saved_value FROM saved") as? [[String:String]]
        XCTAssertEqual(rows?.first?["saved_value"],"37")
        XCTAssertEqual(try Data(contentsOf:history),Data([1,2,3]))
        let copy = parent.appendingPathComponent("副本")
        try fm.copyItem(at:root,to:copy)
        do { try await cold.reconnect(original.id,url:copy); XCTFail("副本不能接管原项目") }
        catch { XCTAssertEqual((error as? DirectoryIssue)?.kind,.identity) }
        let after = try await cold.catalog()
        XCTAssertEqual(after.records.map(\.id),[original.id]); XCTAssertEqual(after.records.first?.grant,same.grant)
        XCTAssertEqual(after.last,original.id)

        let cancelled = DirectoryCommit()
        XCTAssertTrue(cancelled.cancel())
        do { _ = try await cold.create(name:"取消创建",parent:parent,template:.tsx,commit:cancelled); XCTFail("不应创建") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(fm.fileExists(atPath:parent.appendingPathComponent("取消创建").path))
    }

    func testImportCannotOverwriteUnreadableCatalog() async throws {
        try fm.createDirectory(at:store,withIntermediateDirectories:true)
        let catalogFile = store.appendingPathComponent("projects.json")
        let invalid = Data("{".utf8)
        try invalid.write(to:catalogFile)
        let library = ProjectLibrary(base:store)
        do { _ = try await library.discover(root); XCTFail("应保留登记错误") }
        catch { XCTAssertEqual((error as? DirectoryIssue)?.kind,.invalidJSON) }
        XCTAssertEqual(try Data(contentsOf:catalogFile),invalid)
    }

    func testLocalRescanRestoresMovedOriginalWithoutOpeningASameNameReplacement() async throws {
        let library = ProjectLibrary(base:store)
        let originalRecords = try await library.discover(root)
        let record = try XCTUnwrap(originalRecords.first)
        let moved = FolderGrant.documents.appendingPathComponent("已移动 " + UUID().uuidString)
        try fm.moveItem(at:root,to:moved)
        defer { try? fm.removeItem(at:moved) }
        let opened = try await library.open(record.id,remember:true)
        XCTAssertEqual(opened.info.runtimeID,declared)
        let repaired = try await library.catalog()
        XCTAssertEqual(repaired.records.map(\.id),[record.id])
        XCTAssertEqual(repaired.records[0].directoryKey,record.directoryKey)
        XCTAssertEqual(try repaired.records[0].grant.withRoot { ProjectSourceReader.canonical($0) },ProjectSourceReader.canonical(moved))
        // Restore the valid old registration, then put a different project at its recorded location.
        var previous = repaired
        previous.records[0] = record
        try JSONEncoder().encode(previous).write(to:store.appendingPathComponent("projects.json"),options:.atomic)
        try fm.copyItem(at:moved,to:root)
        try write("{\"formatVersion\":1,\"id\":\"" + UUID().uuidString + "\"}","runtime.json")
        do { _ = try await library.open(record.id,remember:true); XCTFail("同名替代目录不能打开") }
        catch { XCTAssertEqual((error as? DirectoryIssue)?.kind,.identity) }
        let final = try await library.catalog()
        XCTAssertEqual(final.records.count,1)
        XCTAssertEqual(final.records[0].grant,record.grant)
    }

    func testSystemVarAliasUsesSameVerifiedDirectory() throws {
        let varURL = URL(fileURLWithPath:"/var/tmp",isDirectory:true)
        let real = URL(fileURLWithPath:"/private/var/tmp/",isDirectory:true)
        try XCTSkipUnless(fm.fileExists(atPath:real.path) && fm.fileExists(atPath:varURL.path),"平台未提供 Darwin /var 别名")
        XCTAssertEqual(ProjectSourceReader.canonical(varURL),ProjectSourceReader.canonical(real))
        let name = "Void 目录 " + UUID().uuidString
        let scratch = varURL.appendingPathComponent(name)
        do { try fm.copyItem(at:root,to:scratch) }
        catch { throw XCTSkip("此测试进程不能写入系统 /var/tmp：" + (error as NSError).domain) }
        defer { try? fm.removeItem(at:scratch) }
        let alias = real.appendingPathComponent(name)
        XCTAssertEqual(try ProjectLibrary.directoryKey(scratch),try ProjectLibrary.directoryKey(alias))
        let snapshot = try ProjectFiles.snapshot(at:scratch)
        XCTAssertEqual(snapshot.files["app/src/main.tsx"],Data(main.utf8))
        XCTAssertEqual(snapshot.revision,try ProjectFiles.snapshot(at:alias).revision)
    }

    @MainActor
    func testRealImportPreviewRebuildFailureRecoveryAndColdReopen() async throws {
        let model = HostModel(storage:store)
        let window = try await PreviewTestWindow(model)
        defer { window.close() }
        func wait(_ condition: () -> Bool) async throws {
            let end = ContinuousClock.now + .seconds(70)
            while !condition() {
                guard ContinuousClock.now < end else { throw RuntimeIssue("等待预览超时") }
                try await Task.sleep(for:.milliseconds(100))
            }
        }
        await model.importDirectory(root)
        try await wait { model.page != nil || model.problem != nil || model.notice != nil }
        XCTAssertEqual(model.page?.nodes.first?.text("value"),"首次预览",model.problem ?? model.notice ?? "")
        let initial = try XCTUnwrap(model.page)
        try atomicEditorSave("export const title = '再次预览';","app/src/detail.ts")
        model.refresh()
        let manual = DirectoryTrace("preview-test")
        model.refresh(force:true,trace:manual)
        XCTAssertTrue(model.busy)
        XCTAssertTrue(DirectoryJournal.shared.recent().contains { $0.request == manual.id && $0.stage == "preview.begin" })
        try await wait { model.page?.id != initial.id || model.problem != nil }
        XCTAssertEqual(model.page?.nodes.first?.text("value"),"再次预览",model.problem ?? "")
        let previous = model.page?.id
        try write("{","app/manifest.json")
        model.refresh(force:true)
        try await wait { model.problem != nil }
        XCTAssertEqual(model.page?.id,previous)
        XCTAssertTrue(model.problem?.contains("目录扫描") == true)
        try write(manifest,"app/manifest.json")
        model.refresh(force:true)
        try await wait { !model.busy && model.problem == nil }
        let restored = HostModel(storage:store)
        let nextWindow = try await PreviewTestWindow(restored)
        defer { nextWindow.close() }
        try await wait { restored.page != nil || restored.problem != nil }
        XCTAssertEqual(restored.page?.nodes.first?.text("value"),"再次预览",restored.problem ?? "")
        XCTAssertEqual(restored.current?.id,model.current?.id)
        await model.showLibrary(); await restored.showLibrary()
    }

    @MainActor
    func testStartupFileWatchCanBeCancelledWhileProviderHoldsDirectory() async throws {
        let found = try await ProjectLibrary(base:store).discover(root)
        let record = try XCTUnwrap(found.first)
        let session = SDKSession(record:record,storage:store,permissions:["files.read"],networkHosts:[])
        defer { session.close() }
        let target = try record.grant.withRoot { $0 }
        let entered = expectation(description:"文件提供商正在协调目录")
        let finished = expectation(description:"测试写者已经结束")
        let release = DispatchSemaphore(value:0)
        DispatchQueue.global().async {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt:target,options:.forReplacing,error:&error) { _ in
                entered.fulfill()
                _ = release.wait(timeout:.now()+6)
            }
            finished.fulfill()
        }
        defer { release.signal() }
        await fulfillment(of:[entered],timeout:3)
        let started = expectation(description:"开始项目首屏需要的文件监听")
        let before = ContinuousClock.now
        let subscription = Task { @MainActor in
            started.fulfill()
            return try await FileSDK().call("watch",SDKArgs(["path":"project/app"]),in:session)
        }
        await fulfillment(of:[started],timeout:2)
        try await Task.sleep(for:.milliseconds(150))
        subscription.cancel()
        do { _ = try await subscription.value; XCTFail("已取消的首屏请求不能登记监听") }
        catch is CancellationError { }
        XCTAssertLessThan(before.duration(to:.now),.seconds(3))
        release.signal()
        await fulfillment(of:[finished],timeout:3)
    }

    @MainActor
    func testRecentTSXPreviewsExistingSQLiteThroughNativeFirstFrame() async throws {
        let library = ProjectLibrary(base:store)
        let found = try await library.discover(root)
        let original = try XCTUnwrap(found.first)
        let originalID = try Data(contentsOf:root.appendingPathComponent("runtime.json"))
        SDKConsent.shared.set(true,for:"database",project:original.id)
        defer { SDKConsent.shared.set(nil,for:"database",project:original.id) }
        let session = SDKSession(record:original,storage:store,permissions:["database"],networkHosts:[])
        let graphics = GraphicsSDK()
        _ = try await graphics.call("execute",SDKArgs(["sql":"CREATE TABLE retained(value TEXT)"]),in:session)
        _ = try await graphics.call("execute",SDKArgs(["sql":"INSERT INTO retained VALUES ('原记录已读取')"]),in:session)
        session.close()
        try write(#"{"dependencies":{"@runtime/ui":"1.0.0","@runtime/sdk":"1.1.0","react":"18.3.1"}}"#,"app/package.json")
        try write("""
        import {ios} from "@runtime/sdk";
          import {render, Form, Section, HStack, Text} from "@runtime/ui";
        async function start() {
          const result = await ios.graphics.query({sql:"SELECT value FROM retained"});
          const title = result.success ? String(result.data[0].value) : result.error.code;
            for (let n = 0; n < 60; n++) {
              const rows = Array.from({length:100}, (_, i) =>
                <HStack key={i}><Text value={String(i)}/><Text value={String(n)}/></HStack>);
              render(<Form><Section title="记录"><Text value={n === 59 ? title : String(n)}/>{rows}</Section></Form>);
            }
        }
        void start();
        ""","app/src/main.tsx")
        let host = HostModel(storage:store)
        await host.load()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where:{ $0.isKeyWindow })
        let window = UIWindow(windowScene:scene)
        window.rootViewController = UIHostingController(rootView:HostView(model:host))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKey() }
        await host.selectRecent(original)
        XCTAssertTrue(host.showingOverview)
        let trace = DirectoryTrace("preview-test")
        host.refresh(force:true,remember:true,trace:trace)
        let deadline = ContinuousClock.now + .seconds(110)
        while (host.busy || host.page?.nodes.first?.children.first?.children.first?.text("value") != "原记录已读取") && host.problem == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for:.milliseconds(100))
        }
        let stages = DirectoryJournal.shared.recent().filter { $0.request == trace.id }.map(\.stage)
        let expected = ["page.sdkMethod","page.nativeCommitReceived","page.contentReady","preview.verifyPage","preview.displayPage","page.firstFrame","preview.saveBuild"]
        XCTAssertEqual(stages.filter { expected.contains($0) },expected)
        XCTAssertTrue(host.page?.displayed == true)
        XCTAssertEqual(host.page?.revision,2)
        XCTAssertEqual(host.page?.nodes.first?.children.first?.children.count,101)
        XCTAssertEqual(host.page?.nodes.first?.children.first?.children.first?.text("value"),"原记录已读取",host.problem ?? "")
        XCTAssertTrue(host.page?.view.window === window)
        XCTAssertEqual(host.current?.id,original.id)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("runtime.json")),originalID)
        await host.showLibrary()
    }
}

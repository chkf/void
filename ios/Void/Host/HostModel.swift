import Foundation
import SwiftUI

enum HostPage {
    case overview
    case workspace(ProjectTemplate)
    case swiftUI(UUID)
    case script(ProjectPage)
}

@MainActor
final class HostModel: ObservableObject {
    @Published var records: [ProjectRecord] = []
    @Published private(set) var current: ProjectRecord?
    @Published private(set) var screen: HostPage?
    @Published private(set) var mode: UIMode?
    var workspaceTemplate: ProjectTemplate? {
        if case let .workspace(template) = screen { return template }
        return nil
    }
    var showingOverview: Bool {
        if case .overview = screen { return true }
        return false
    }
    var shouldMonitor: Bool {
        !showingOverview && workspaceTemplate == nil && !userStoppedScanning &&
            (screen != nil || waitingEntry != nil || problem != nil)
    }
    var page: ProjectPage? {
        if case let .script(value) = screen { return value }
        return nil
    }
    @Published private(set) var candidate: ProjectPage?
    @Published private(set) var presentingPage: ProjectPage?
    @Published private(set) var compiler: CompilerPage?
    @Published private(set) var busy = false
    @Published var notice: String?
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var problem: String?
    @Published private(set) var waitingEntry: String?
    @Published private(set) var permissions: [String] = []
    @Published private(set) var log: [String] = []
    let folders = FolderRequests()
    @Published private(set) var scanStatus: String?
    private var userStoppedScanning = false
    private var scanTrace: DirectoryTrace?
    private let library: ProjectLibrary
    private let products: ProductStore
    private let previewRecovery: PreviewRecovery
    private var recoveredAttempt: PreviewAttempt?
    var interruptedRequestID: UUID? { recoveredAttempt?.request }
    private let usesAppCatalog: Bool
    private let storage: URL
    private var networkHosts: [String] = []
    private var loaded = false
    #if DEBUG && targetEnvironment(simulator)
    @Published private(set) var simulatorFixtureReady = false
    #endif
    private var generation = UUID()
    private var inspected: String?
    private var work: Task<Void, Never>?
    private var watch: SourceWatcher?
    private var needsScan = false

    init(storage: URL? = nil) {
        let base = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("void")
        library = ProjectLibrary(base: base)
        self.storage = base
        previewRecovery = PreviewRecovery(storage:base)
        usesAppCatalog = storage == nil
        products = ProductStore(base: base.appendingPathComponent("Builds"))
        folders.process = { [weak self] request,url in
            guard let self else { throw CancellationError() }
            return try await self.processDirectory(request,url)
        }
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            #if DEBUG && targetEnvironment(simulator)
            try await SimulatorPickerFixture.prepareIfRequested()
            defer { simulatorFixtureReady = SimulatorPickerFixture.directory != nil }
            #endif
            let catalog = try await list()
            var interrupted = try await previewRecovery.pending()
            if interrupted == nil, usesAppCatalog, let id = catalog.last,
               let request = PreviewRecovery.interruptedLegacyRequest(DirectoryJournal.shared.recent()) {
                let previous = PreviewAttempt(request:request,project:id,stage:.legacyPreparation)
                try await previewRecovery.mark(previous,starting:true)
                interrupted = previous
            }
            if let interrupted, let original = records.first(where:{ $0.id == interrupted.project }) {
                recoveredAttempt = interrupted
                let stage = PreviewRecovery.interruptionTitle(interrupted,entries:DirectoryJournal.shared.recent())
                recoveryMessage = "「" + original.name + "」上次在「" + stage + "」时中断。"
                DirectoryTrace("recovery",id:interrupted.request).event("preview.interrupted",interrupted.stage.rawValue)
            } else if usesAppCatalog, let (id,stage) = PreviewRecovery.interruptedLocalScan(DirectoryJournal.shared.recent()) {
                recoveryMessage = "上次本机目录检查中断，可在目录诊断查看最后一步。"
                DirectoryTrace("local",id:id).event("local.interrupted",stage)
            } else if let id = catalog.last, let record = records.first(where:{ $0.id == id }) {
                await open(record)
            }
        } catch { notice = error.localizedDescription }
    }

    @discardableResult
    private func list() async throws -> Catalog {
        let value = try await library.catalog()
        records = value.recent
        return value
    }

    func create(_ name: String, parent: URL?, template: ProjectTemplate = .swiftUI) async {
        do { let record = try await library.create(name: name, parent: parent, template: template); try await list(); await open(record) }
        catch { notice = error.localizedDescription }
    }

    private func processDirectory(_ r: FolderRequest, _ url: URL) async throws -> String {
        func checkRequest() throws {
            try Task.checkCancellation()
            guard current?.id == r.origin, folders.request?.id == r.id else { throw CancellationError() }
        }
        try checkRequest()
        r.trace.event("grant.resolve")
        let found: [ProjectRecord]
        let message: String
        switch r.purpose {
        case .create(let name,let template):
            found = [try await library.create(name:name,parent:url,template:template,trace:r.trace,commit:r.commit)]
            message = "已创建「" + name + "」"
        case .importFolder,.local:
            found = try await library.discover(url,localRoot:r.purpose == .local,trace:r.trace,commit:r.commit)
            message = found.count == 1 ? "已找到「" + found[0].name + "」" : "已找到 \(found.count) 个项目"
        case .reconnect(let id):
            guard id == r.origin else { throw CancellationError() }
            try await library.reconnect(id,url:url,trace:r.trace,commit:r.commit)
            found = try await library.catalog().recent.filter { $0.id == id }
            message = "已核验原项目目录"
        }
        try Task.checkCancellation()
        try await list()
        guard folders.request?.id == r.id, current?.id == r.origin else { return message }
        if r.purpose != .local, found.count == 1 {
            if current?.id == found[0].id {
                current = found[0]
                refresh(force:true,remember:true,trace:r.trace)
            } else { await open(found[0],from:r) }
        }
        return message
    }

    func importDirectory(_ url: URL) async {
        let trace = DirectoryTrace("import")
        do {
            let result = try await library.discover(url,trace:trace)
            try await list()
            if result.count == 1 { await open(result[0]) }
            trace.event("import.result","OK")
        } catch { trace.event("import.result","失败",error:error); notice = DirectoryIssue.safeMessage(error) }
    }

    func rename(_ name: String) async {
        guard let current else { return }
        do {
            try await library.rename(current, name: name)
            try await list()
            self.current = records.first { $0.id == current.id }
            refresh()
        } catch { notice = error.localizedDescription }
    }

    private func clear() {
        generation = UUID()
        work?.cancel()
        compiler?.stop()
        compiler = nil
        work = nil
        watch?.stop()
        watch = nil
        candidate?.onFailure?("项目已切换")
        candidate?.stop()
        candidate = nil
        presentingPage = nil
        page?.stop()
        screen = nil
        mode = nil
        inspected = nil
        needsScan = false
        busy = false
        scanStatus = nil
        scanTrace = nil
        userStoppedScanning = false
        permissions = []
        networkHosts = []
        problem = nil
        waitingEntry = nil
        log = []
    }

    func selectRecent(_ record: ProjectRecord) async {
        if record.pendingTemplate != nil { await open(record); return }
        folders.changeProject(to:record.id)
        clear()
        current = record
        screen = .overview
        await acknowledgeOtherInterruption(choosing:record.id)
    }

    private func acknowledgeOtherInterruption(choosing id: UUID) async {
        guard let previous = recoveredAttempt, previous.project != id else { return }
        do {
            // Only acknowledge the interruption the library actually showed the user.
            // A newer in-flight preview owns its own marker.
            try await previewRecovery.finish(previous.request)
            if recoveredAttempt?.request == previous.request {
                recoveredAttempt = nil
                recoveryMessage = nil
            }
        } catch { DirectoryTrace("recovery",id:previous.request).event("preview.recoveryWriteFailed",error:error) }
    }

    func open(_ record: ProjectRecord, from request: FolderRequest? = nil) async {
        if request?.id != folders.request?.id || request == nil { folders.changeProject(to:record.id) }
        clear()
        recoveryMessage = nil
        current = record
        let token = generation
        await acknowledgeOtherInterruption(choosing:record.id)
        guard generation == token, current?.id == record.id else { return }
        if let template = record.pendingTemplate {
            screen = .workspace(template)
            mode = template == .swiftUI ? .swiftui : .native
            do {
                let declared = try await library.selectWorkspace(record.id)
                guard current?.id == record.id else { return }
                permissions = declared
                try await list()
            }
            catch { if current?.id == record.id { notice = error.localizedDescription } }
        } else {
            refresh(force:true,remember:true,trace:request?.trace)
        }
    }

    func removeRecent(_ id: UUID) async {
        if current?.id == id { folders.changeProject(to:nil) }
        do {
            try await library.removeRecent(id)
            if current?.id == id { clear(); current = nil }
            try await list()
        } catch { notice = error.localizedDescription }
    }

    func showLibrary() async {
        folders.changeProject(to:nil)
        do {
            try await library.forgetLast()
            clear()
            current = nil
            try await list()
        } catch { notice = error.localizedDescription }
    }

    func monitor() async {
        guard let record = current, shouldMonitor else { return }
        let observer = try? await SourceWatcher.start(grant:record.grant) { [weak self] in
            Task { @MainActor in if self?.current?.id == record.id { self?.refresh() } }
        }
        guard !Task.isCancelled, current?.id == record.id else { observer?.stop(); return }
        watch = observer
        defer { observer?.stop(); if observer === watch { watch = nil } }
        while !Task.isCancelled && current?.id == record.id {
            do { try await Task.sleep(for: .seconds(4)) } catch { break }
            if current?.id == record.id, shouldMonitor, work == nil { refresh() }
        }
    }

    func cancelScan() {
        guard let work else { return }
        userStoppedScanning = true; needsScan = false
        scanTrace?.event("preview.cancel")
        work.cancel()
        candidate?.onFailure?("已取消预览")
        scanStatus = "已取消预览"
    }

    func memoryWarning() {
        guard busy, work != nil else { return }
        scanTrace?.event("preview.memoryWarning")
        cancelScan()
        problem = "系统报告内存紧张，本次预览已停止。可返回原项目后重试。"
        scanStatus = "本次预览已停止"
    }

    func refresh(force: Bool = false, remember: Bool = false, previous: Bool = false, trace input: DirectoryTrace? = nil) {
        guard let record = current, force || (!showingOverview && workspaceTemplate == nil && !userStoppedScanning) else { return }
        if force { userStoppedScanning = false }
        if let pending = work {
            guard force else { needsScan = true; return }
            // A user-initiated build must take over even while a silent provider scan is waiting.
            generation = UUID()
            scanTrace?.event("preview.superseded")
            pending.cancel()
            compiler?.stop()
            compiler = nil
            candidate?.onFailure?("已开始新的预览请求")
            candidate = nil
            needsScan = false
        }
        let token = generation
        let trace = input ?? (force ? DirectoryTrace("preview") : nil)
        scanTrace = trace
        if force {
            busy = true; scanStatus = "正在扫描项目目录"; trace?.event("preview.begin")
        }
        work = Task {
            defer {
                if generation == token {
                    work = nil
                    busy = false
                    if !userStoppedScanning { scanStatus = nil }
                    scanTrace = nil
                    if needsScan && !userStoppedScanning {
                        needsScan = false
                        refresh(force:workspaceTemplate != nil)
                    }
                }
            }
            let diagnostic = trace ?? DirectoryTrace("preview")
            let attemptID = diagnostic.id
            var marked = false
            @MainActor func stage(_ stage: PreviewStage) async throws {
                try check(token)
                let attempt = PreviewAttempt(request:attemptID,project:record.id,stage:stage)
                if !marked, trace == nil { diagnostic.event("preview.begin") }
                try await previewRecovery.mark(attempt,starting:!marked)
                marked = true
                try check(token)
                scanTrace = diagnostic
                scanStatus = stage.title
                diagnostic.event("preview." + stage.rawValue)
            }
            @MainActor func run() async {
                var scanned = false
                do {
                    if force { try await stage(.scan) }
                    if !force && !remember, let inspected {
                        let revision = try await library.revision(record.id,trace:trace)
                        try check(token)
                        if revision == inspected { return }
                    }
                    let snapshot = try await library.open(record.id,remember:remember,trace:trace)
                    scanned = true
                    try check(token)
                    waitingEntry = nil
                    mode = snapshot.info.mode
                    permissions = snapshot.info.permissions
                    networkHosts = snapshot.info.networkHosts
                    if let sdk = page?.sdk, !sdk.declared.isSubset(of: Set(permissions)) || !sdk.networkHosts.isSubset(of: Set(networkHosts.map { $0.lowercased() })) {
                        sdk.close()
                    }
                    if force || remember || current?.name != snapshot.info.name || current?.version != snapshot.info.version {
                        try await list()
                        try check(token)
                        current = records.first { $0.id == record.id }
                    }
                    guard force || inspected != snapshot.revision else { return }
                    inspected = snapshot.revision
                    busy = true
                    problem = nil
                    let verifiedRecord = current ?? record
                    try await stage(.cache)
                    if snapshot.info.mode == .swiftui {
                        try await Task.detached { try CompiledProject.validate(snapshot) }.value
                        try check(token)
                        try await finishFirstPreview(record, token: token)
                        if force || screen == nil || page != nil {
                            page?.stop()
                            screen = .swiftUI(UUID())
                        }
                        trace?.event("preview.result","OK")
                        log.append("已打开 SwiftUI 页面 " + snapshot.revision.prefix(12))
                        return
                    }
                    let product: Product
                    if previous {
                        guard let saved = try await products.accepted(record.id, previous: true) else { throw RuntimeIssue("还没有可恢复的上一版本") }
                        product = saved
                    } else if remember, let cached = try? await products.matching(snapshot.revision, project: record.id) {
                        product = cached
                    } else {
                        try await stage(.compiler)
                        product = try await BuildEngine.build(snapshot,trace:diagnostic,showCompiler:{ page in
                            if self.generation == token { self.compiler = page }
                        }) { try await stage(.compile) }
                        try await stage(.verify)
                        let latest = try await library.revision(record.id,trace:trace)
                        try check(token)
                        guard latest == snapshot.revision else { needsScan = true; return }
                    }
                    try await stage(.firstFrame)
                    try await activate(product,record:verifiedRecord,token:token,expected:previous ? nil : snapshot.revision,trace:diagnostic,stage:stage)
                    trace?.event("preview.result","OK")
                } catch {
                    guard generation == token, !Task.isCancelled else { return }
                    let missing = error as? MissingProjectEntry
                    waitingEntry = missing?.path
                    if let missing {
                        mode = missing.mode
                        inspected = nil
                    }
                    let scanError = !scanned || error is DirectoryIssue || error is FolderAccessIssue || missing != nil
                    let e = error as NSError
                    let message = scanError || error is RuntimeIssue ? DirectoryIssue.safeMessage(error) : "预览失败（\(e.domain) \(e.code)）"
                    let detail = (scanError ? "目录扫描 · " : "") + message
                    if trace != nil || problem != detail {
                        let failureTrace = trace ?? DirectoryTrace("preview")
                        failureTrace.event(scanError ? "scan.result" : "preview.result","失败",error:error)
                        log.append(detail)
                    }
                    problem = detail
                    if scanError { inspected = nil }
                    if let issue = error as? DirectoryIssue, [.provider,.timeout,.unreadable,.identity,.sourceLimit].contains(issue.kind) {
                        userStoppedScanning = true
                        needsScan = false
                        scanStatus = "目录检查已结束"
                    }
                    if let issue = error as? DirectoryIssue, [.unreadable,.identity,.outside,.link].contains(issue.kind) {
                        page?.sdk.close()
                        permissions = []
                    }
                    if mode != .swiftui, screen == nil, (error as? DirectoryIssue)?.kind != .sourceLimit, let accepted = try? await products.accepted(record.id) {
                        do {
                            try await stage(.firstFrame)
                            try await activate(accepted,record:record,token:token,expected:nil,trace:diagnostic,stage:stage)
                            problem = detail
                        } catch { if generation == token { problem = detail + "\n" + error.localizedDescription } }
                    }
                }
            }
            await run()
            if marked {

                do { try await previewRecovery.finish(attemptID) }
                catch { diagnostic.event("preview.recoveryWriteFailed",error:error) }
            }
        }
    }

    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
    }

    private func finishFirstPreview(_ record: ProjectRecord, token: UUID) async throws {
        guard record.pendingTemplate != nil else { return }
        try await library.finishFirstPreview(record.id)
        try await list()
        try check(token)
        current = records.first { $0.id == record.id }
    }

    private func activate(_ product: Product, record: ProjectRecord, token: UUID, expected: String?, trace: DirectoryTrace,
                          stage: @MainActor (PreviewStage) async throws -> Void) async throws {
        try check(token)
        let next = try ProjectPage(product:product,record:record,storage:storage,permissions:permissions,networkHosts:networkHosts,trace:trace)
        candidate = next
        let confirmation = DirectoryCommit()
        defer {
            if presentingPage === next { presentingPage = nil }
            if candidate === next { candidate = nil }
            if page !== next { next.stop() }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var waiting = true
            func finish(_ result: Result<Void, Error>) {
                guard waiting else { return }
                waiting = false
                continuation.resume(with: result)
            }
            next.onReady = { finish(.success(())) }
            next.onFailure = { message in
                _ = confirmation.cancel()
                finish(.failure(RuntimeIssue(message)))
            }
            Task {
                do { try await next.start() } catch { finish(.failure(error)) }
            }
        }
        try check(token)
        if let expected {
            try await stage(.verifyPage)
            let latest = try await library.revision(record.id,trace:trace)
            try check(token)
            guard latest == expected else { needsScan = true; return }
        }
        if let failure = next.failure { throw RuntimeIssue(failure) }
        try await stage(.displayPage)
        presentingPage = next
        try await next.waitForDisplay()
        try check(token)
        if let failure = next.failure { throw RuntimeIssue(failure) }
        try await stage(.saveBuild)
        do { try await products.confirm(product,project:record.id,commit:confirmation) }
        catch {
            if let failure = next.failure { throw RuntimeIssue(failure) }
            throw error
        }
        try check(token)
        try await finishFirstPreview(record, token: token)
        page?.stop()
        next.onReady = nil
        next.onFailure = { [weak self, weak next] message in
            if let self, let next, self.page === next { self.problem = message; self.log.append(message) }
        }
        screen = .script(next)
        log.append("已打开 " + product.revision.prefix(12))
    }
}

import Foundation
import SwiftUI

enum HostPage {
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
    var page: ProjectPage? {
        if case let .script(value) = screen { return value }
        return nil
    }
    @Published private(set) var candidate: ProjectPage?
    @Published private(set) var busy = false
    @Published var notice: String?
    @Published private(set) var problem: String?
    @Published private(set) var permissions: [String] = []
    @Published private(set) var log: [String] = []
    private let library: ProjectLibrary
    private let products: ProductStore
    private let storage: URL
    private var networkHosts: [String] = []
    private var loaded = false
    private var generation = UUID()
    private var inspected: String?
    private var work: Task<Void, Never>?
    private var watch: SourceWatcher?
    private var needsScan = false
    private var requestedRestart = false
    private var requestedPrevious = false

    init(storage: URL? = nil) {
        let base = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("void")
        library = ProjectLibrary(base: base)
        self.storage = base
        products = ProductStore(base: base.appendingPathComponent("Builds"))
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            let catalog = try await list()
            if let id = catalog.last, let record = records.first(where: { $0.id == id }) { await open(record) }
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

    func importDirectory(_ url: URL) async {
        do {
            let result = try await library.discover(url)
            try await list()
            if result.count == 1 { await open(result[0]) }
        } catch { notice = error.localizedDescription }
    }

    func reconnect(_ url: URL) async {
        guard let id = current?.id else { return }
        do {
            try await library.reconnect(id, url: url)
            try await list()
            if let record = records.first(where: { $0.id == id }) { await open(record) }
        } catch { notice = error.localizedDescription }
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
        work = nil
        watch?.stop()
        watch = nil
        candidate?.onFailure?("项目已切换")
        candidate?.stop()
        candidate = nil
        page?.stop()
        screen = nil
        mode = nil
        inspected = nil
        needsScan = false
        requestedRestart = false
        requestedPrevious = false
        busy = false
        permissions = []
        networkHosts = []
        problem = nil
        log = []
    }

    func open(_ record: ProjectRecord) async {
        clear()
        current = record
        if let template = record.pendingTemplate {
            screen = .workspace(template)
            mode = template == .swiftUI ? .swiftui : .native
            do { try await library.selectWorkspace(record.id); try await list() }
            catch { if current?.id == record.id { notice = error.localizedDescription } }
        } else {
            refresh(force: true, remember: true)
        }
    }

    func removeRecent(_ id: UUID) async {
        do {
            try await library.removeRecent(id)
            if current?.id == id { clear(); current = nil }
            try await list()
        } catch { notice = error.localizedDescription }
    }

    func showLibrary() async {
        do {
            try await library.forgetLast()
            clear()
            current = nil
            try await list()
        } catch { notice = error.localizedDescription }
    }

    func monitor() async {
        guard let record = current, workspaceTemplate == nil else { return }
        let observer = try? record.grant.withRoot { url in
            SourceWatcher(root: url) { [weak self] in
                Task { @MainActor in if self?.current?.id == record.id { self?.refresh() } }
            }
        }
        watch = observer
        defer { observer?.stop(); if observer === watch { watch = nil } }
        while !Task.isCancelled && current?.id == record.id {
            refresh()
            do { try await Task.sleep(for: .seconds(4)) } catch { break }
        }
    }

    func refresh(force: Bool = false, remember: Bool = false, previous: Bool = false) {
        guard let record = current, force || workspaceTemplate == nil else { return }
        if work != nil {
            needsScan = true
            if force { requestedRestart = true; requestedPrevious = previous }
            return
        }
        let token = generation
        if force { busy = true }
        work = Task {
            defer {
                if generation == token {
                    work = nil
                    busy = false
                    if needsScan {
                        let restart = requestedRestart, rollback = requestedPrevious
                        needsScan = false
                        requestedRestart = false
                        requestedPrevious = false
                        refresh(force: restart || workspaceTemplate != nil, previous: rollback)
                    }
                }
            }
            do {
                let snapshot = try await library.open(record.id, remember: remember)
                try check(token)
                mode = snapshot.info.mode
                permissions = snapshot.info.permissions
                networkHosts = snapshot.info.networkHosts
                if let sdk = page?.sdk, !sdk.declared.isSubset(of: Set(permissions)) || !sdk.networkHosts.isSubset(of: Set(networkHosts.map { $0.lowercased() })) {
                    sdk.close()
                }
                if remember || current?.name != snapshot.info.name || current?.version != snapshot.info.version {
                    try await list()
                    try check(token)
                    current = records.first { $0.id == record.id }
                }
                guard force || inspected != snapshot.revision else { return }
                inspected = snapshot.revision
                busy = true
                problem = nil
                if snapshot.info.mode == .swiftui {
                    try await Task.detached { try CompiledProject.validate(snapshot) }.value
                    try check(token)
                    try await finishFirstPreview(record, token: token)
                    if force || screen == nil || page != nil {
                        page?.stop()
                        screen = .swiftUI(UUID())
                    }
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
                    product = try await BuildEngine.build(snapshot)
                    let latest = try await library.open(record.id, remember: false)
                    try check(token)
                    guard latest.revision == snapshot.revision else { needsScan = true; return }
                }
                try await activate(product, record: record, token: token, expected: previous ? nil : snapshot.revision)
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                let detail = error.localizedDescription
                if problem != detail { log.append(detail) }
                problem = detail
                let code = (error as NSError)
                if error is FolderAccessIssue || (code.domain == NSCocoaErrorDomain && code.code == NSFileReadNoPermissionError) {
                    page?.stop()
                    if workspaceTemplate == nil { screen = nil }
                    inspected = nil
                    permissions = []
                    return
                }
                if mode != .swiftui, screen == nil, let accepted = try? await products.accepted(record.id) {
                    do { try await activate(accepted, record: record, token: token, expected: nil); problem = detail }
                    catch { if generation == token { problem = detail + "\n" + error.localizedDescription } }
                }
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

    private func activate(_ product: Product, record: ProjectRecord, token: UUID, expected: String?) async throws {
        try check(token)
        let next = try ProjectPage(product: product, record: record, storage: storage, permissions: permissions, networkHosts: networkHosts)
        candidate = next
        defer {
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
            next.onFailure = { finish(.failure(RuntimeIssue($0))) }
            Task {
                do { try await next.start() } catch { finish(.failure(error)) }
            }
        }
        try check(token)
        if let expected {
            let latest = try await library.open(record.id, remember: false)
            try check(token)
            guard latest.revision == expected else { needsScan = true; return }
        }
        try await products.confirm(product, project: record.id)
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

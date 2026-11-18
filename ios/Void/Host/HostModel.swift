import Foundation
import SwiftUI

@MainActor
final class HostModel: ObservableObject {
    @Published var records: [ProjectRecord] = []
    @Published private(set) var current: ProjectRecord?
    @Published private(set) var page: ProjectPage?
    @Published private(set) var candidate: ProjectPage?
    @Published private(set) var busy = false
    @Published var notice: String?
    @Published private(set) var problem: String?
    @Published private(set) var permissions: [String] = []
    @Published private(set) var log: [String] = []
    private let library: ProjectLibrary
    private let products: ProductStore
    private var loaded = false
    private var generation = UUID()
    private var inspected: String?
    private var work: Task<Void, Never>?
    private var watch: SourceWatcher?
    private var needsScan = false

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("void")
        library = ProjectLibrary(base: base)
        products = ProductStore(base: base.appendingPathComponent("Builds"))
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            let catalog = try await list()
            if let id = catalog.last, let record = records.first(where: { $0.id == id }) { open(record) }
        } catch { notice = error.localizedDescription }
    }

    @discardableResult
    private func list() async throws -> Catalog {
        let value = try await library.catalog()
        records = value.records.sorted { $0.opened > $1.opened }
        return value
    }

    func create(_ name: String, parent: URL?) async {
        do { let record = try await library.create(name: name, parent: parent); try await list(); open(record) }
        catch { notice = error.localizedDescription }
    }

    func importDirectory(_ url: URL) async {
        do {
            let result = try await library.discover(url)
            try await list()
            if result.count == 1 { open(result[0]) }
        } catch { notice = error.localizedDescription }
    }

    func reconnect(_ url: URL) async {
        guard let id = current?.id else { return }
        do {
            try await library.reconnect(id, url: url)
            try await list()
            if let record = records.first(where: { $0.id == id }) { open(record) }
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
        page = nil
        inspected = nil
        needsScan = false
        busy = false
        permissions = []
        problem = nil
        log = []
    }

    func open(_ record: ProjectRecord) {
        clear()
        current = record
        refresh(force: true, remember: true)
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
        guard let record = current else { return }
        let observer = try? record.grant.withRoot { url in
            SourceWatcher(root: url) { [weak self] in
                Task { @MainActor in if self?.current?.id == record.id { self?.refresh() } }
            }
        }
        watch = observer
        defer { if let observer, observer === watch { observer.stop(); watch = nil } }
        while !Task.isCancelled && current?.id == record.id {
            refresh()
            do { try await Task.sleep(for: .seconds(4)) } catch { break }
        }
    }

    func refresh(force: Bool = false, remember: Bool = false, previous: Bool = false) {
        guard let record = current else { return }
        if work != nil { needsScan = true; return }
        let token = generation
        work = Task {
            defer {
                if generation == token {
                    work = nil
                    busy = false
                    if needsScan { needsScan = false; refresh() }
                }
            }
            do {
                let snapshot = try await library.open(record.id, remember: remember)
                try check(token)
                permissions = snapshot.info.permissions
                if remember || current?.name != snapshot.info.name || current?.version != snapshot.info.version {
                    try await list()
                    try check(token)
                    current = records.first { $0.id == record.id }
                }
                guard force || inspected != snapshot.revision else { return }
                inspected = snapshot.revision
                busy = true
                problem = nil
                let product: Product
                if previous {
                    guard let saved = try await products.accepted(record.id, previous: true) else { throw RuntimeIssue("还没有可恢复的上一版本") }
                    product = saved
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
                if page == nil, let accepted = try? await products.accepted(record.id) {
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

    private func activate(_ product: Product, record: ProjectRecord, token: UUID, expected: String?) async throws {
        try check(token)
        let next = try ProjectPage(product: product, projectID: record.id)
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
        page?.stop()
        next.onReady = nil
        next.onFailure = { [weak self, weak next] message in
            if let self, let next, self.page === next { self.problem = message; self.log.append(message) }
        }
        page = next
        log.append("已打开 " + product.revision.prefix(12))
    }
}

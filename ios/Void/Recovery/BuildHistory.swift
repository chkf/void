import Foundation

struct BuildHistory: Codable {
    var current: String?
    var previous: String?
}

actor ProductStore {
    private struct Index: Codable {
        let entry: String
        let mode: UIMode
        let revision: String
        let paths: [String]
    }

    let base: URL
    init(base: URL) { self.base = base }

    private func directory(_ id: UUID) -> URL { base.appendingPathComponent(id.uuidString) }
    private func buildKey(_ revision: String) throws -> String {
        let key = revision + "-" + String(decoding: try Toolchain.read("build-id.txt"), as: UTF8.self)
        guard ProjectFiles.component(key) else { throw RuntimeIssue("构建标识无效") }
        return key
    }
    private func history(_ id: UUID) throws -> BuildHistory {
        let url = directory(id).appendingPathComponent("history.json")
        if !FileManager.default.fileExists(atPath: url.path) { return BuildHistory() }
        return try JSONDecoder().decode(BuildHistory.self, from: Data(contentsOf: url))
    }

    func accepted(_ id: UUID, previous: Bool = false) throws -> Product? {
        let pointer = try history(id)
        guard let version = previous ? pointer.previous : pointer.current else { return nil }
        guard ProjectFiles.component(version) else { throw RuntimeIssue("构建记录损坏") }
        let parent = directory(id)
        let bundle = parent.appendingPathComponent(version + ".product")
        var product: Product
        if FileManager.default.fileExists(atPath:bundle.path) {
            let index = try JSONDecoder().decode(Index.self,from:Data(contentsOf:bundle.appendingPathComponent("index.json")))
            var files: [String:Data] = [:]
            for (offset,path) in index.paths.enumerated() {
                try Task.checkCancellation()
                guard ProjectFiles.safePath(path), files[path] == nil else { throw RuntimeIssue("构建资源目录损坏") }
                files[path] = try Data(contentsOf:bundle.appendingPathComponent(String(offset)),options:.mappedIfSafe)
            }
            guard files[index.entry] != nil else { throw RuntimeIssue("构建记录缺少入口") }
            product = Product(entry:index.entry,files:files,mode:index.mode,revision:index.revision)
        } else {
            let legacy = parent.appendingPathComponent(version + ".json")
            product = try JSONDecoder().decode(Product.self,from:Data(contentsOf:legacy,options:.mappedIfSafe))
        }
        product.storedKey = version
        return product
    }

    func matching(_ revision: String, project id: UUID) throws -> Product? {
        let current = try history(id).current
        if current == (try buildKey(revision)) { return try accepted(id) }
        // The released dev.10 product carries its own v1 renderer. Reopen an
        // unchanged native project in place, retaining both history pointers.
        let dev10 = "8f54b1ef5cb30086abd34dd6bc023b93e37a660ea339c51fe8761ce287056504"
        guard current == revision + "-" + dev10, let product = try accepted(id),
              product.mode == .native, product.revision == revision else { return nil }
        return product
    }

    func confirm(_ product: Product, project id: UUID, commit: DirectoryCommit? = nil) throws {
        let folder = directory(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let key = try product.storedKey ?? buildKey(product.revision)
        guard ProjectFiles.component(key) else { throw RuntimeIssue("构建标识无效") }
        let fm = FileManager.default
        let bundle = folder.appendingPathComponent(key + ".product")
        if !fm.fileExists(atPath:bundle.path), !fm.fileExists(atPath:folder.appendingPathComponent(key + ".json").path) {
            guard product.files[product.entry] != nil else { throw RuntimeIssue("构建资源缺少入口") }
            let staging = folder.appendingPathComponent(".pending-" + UUID().uuidString)
            try fm.createDirectory(at:staging,withIntermediateDirectories:false)
            defer { if fm.fileExists(atPath:staging.path) { try? fm.removeItem(at:staging) } }
            let paths = product.files.keys.sorted()
            for (offset,path) in paths.enumerated() {
                try Task.checkCancellation()
                guard ProjectFiles.safePath(path), let bytes = product.files[path] else { throw RuntimeIssue("构建资源路径无效") }
                try bytes.write(to:staging.appendingPathComponent(String(offset)))
            }
            let index = Index(entry:product.entry,mode:product.mode,revision:product.revision,paths:paths)
            try JSONEncoder().encode(index).write(to:staging.appendingPathComponent("index.json"))
            try Task.checkCancellation()
            do { try fm.moveItem(at:staging,to:bundle) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                guard fm.fileExists(atPath:bundle.appendingPathComponent("index.json").path) else { throw error }
            }
        }
        try Task.checkCancellation()
        var pointer = try history(id)
        try commit?.begin()
        if pointer.current != key {
            pointer.previous = pointer.current
            pointer.current = key
            try JSONEncoder().encode(pointer).write(to: folder.appendingPathComponent("history.json"), options: .atomic)
        }
    }
}

import Foundation

struct BuildHistory: Codable {
    var current: String?
    var previous: String?
}

actor ProductStore {
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
        let url = directory(id).appendingPathComponent(version + ".json")
        return try JSONDecoder().decode(Product.self, from: Data(contentsOf: url))
    }

    func matching(_ revision: String, project id: UUID) throws -> Product? {
        guard try history(id).current == buildKey(revision) else { return nil }
        return try accepted(id)
    }

    func confirm(_ product: Product, project id: UUID) throws {
        let folder = directory(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var pointer = try history(id)
        let key = try buildKey(product.revision)
        let url = folder.appendingPathComponent(key + ".json")
        if !FileManager.default.fileExists(atPath: url.path) { try JSONEncoder().encode(product).write(to: url, options: .atomic) }
        if pointer.current != key {
            pointer.previous = pointer.current
            pointer.current = key
            try JSONEncoder().encode(pointer).write(to: folder.appendingPathComponent("history.json"), options: .atomic)
        }
    }
}

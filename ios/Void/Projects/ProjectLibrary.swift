import Foundation

struct ProjectRecord: Codable, Identifiable {
    let id: UUID
    var grant: FolderGrant
    var directoryKey: String
    var declaredID: String?
    var name: String
    var version: String
    var opened: Date
}

struct Catalog: Codable {
    var records: [ProjectRecord] = []
    var last: UUID?
}

actor ProjectLibrary {
    private let file: URL
    init(base: URL) { file = base.appendingPathComponent("projects.json") }

    func catalog() throws -> Catalog {
        if !FileManager.default.fileExists(atPath: file.path) { return Catalog() }
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: file))
    }

    private func save(_ catalog: Catalog) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(catalog).write(to: file, options: .atomic)
    }

    private func key(_ url: URL) throws -> String {
        try ProjectFiles.checkLink(url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = attrs[.systemNumber] as? NSNumber, let inode = attrs[.systemFileNumber] as? NSNumber,
              inode.uint64Value != 0 else { throw RuntimeIssue("文件服务商未提供可验证的目录标识") }
        return device.stringValue + "/" + inode.stringValue
    }

    func create(name: String, parent: URL?) throws -> ProjectRecord {
        var grant = try parent.map { try FolderGrant.selected($0) } ?? FolderGrant(bookmark: nil, child: "")
        _ = try grant.coordinated(write: true) { try ProjectFiles.create(name, in: $0) }
        grant.child = name
        return try register([grant])[0]
    }

    func discover(_ url: URL) throws -> [ProjectRecord] {
        let grant = try FolderGrant.selected(url)
        let children: [String] = try grant.coordinated { root in
            let fm = FileManager.default
            if fm.fileExists(atPath: root.appendingPathComponent("app/manifest.json").path)
                || fm.fileExists(atPath: root.appendingPathComponent("runtime.json").path) { return [""] }
            return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .filter { fm.fileExists(atPath: $0.appendingPathComponent("app/manifest.json").path)
                    || fm.fileExists(atPath: $0.appendingPathComponent("runtime.json").path) }
                .map(\.lastPathComponent).sorted()
        }
        guard !children.isEmpty else { throw RuntimeIssue("未找到项目，请选择包含 app/manifest.json 的目录或它的上一级") }
        return try register(children.map { FolderGrant(bookmark: grant.bookmark, child: $0) })
    }

    private func register(_ grants: [FolderGrant]) throws -> [ProjectRecord] {
        var catalog = try catalog()
        var found: [ProjectRecord] = []
        for grant in grants {
            let record = try grant.coordinated { root -> ProjectRecord in
                let identity = try key(root)
                let metadata = try? ProjectFiles.snapshot(at: root).info
                if var existing = catalog.records.first(where: { $0.directoryKey == identity }) {
                    if let expected = existing.declaredID, let actual = metadata?.declaredID, expected != actual {
                        throw RuntimeIssue("已登记目录的项目身份发生变化")
                    }
                    existing.grant = grant
                    return existing
                }
                if let id = metadata?.declaredID, catalog.records.contains(where: { $0.declaredID == id }) {
                    throw RuntimeIssue("另一目录已登记相同的项目 id，请为副本设置独立的 runtime.json id")
                }
                return ProjectRecord(id: UUID(), grant: grant, directoryKey: identity, declaredID: metadata?.declaredID,
                                     name: metadata?.name ?? root.lastPathComponent, version: metadata?.version ?? "", opened: Date())
            }
            catalog.records.removeAll { $0.id == record.id }
            catalog.records.append(record)
            found.append(record)
        }
        try save(catalog)
        return found
    }

    func open(_ id: UUID, remember: Bool) throws -> SourceSnapshot {
        var catalog = try catalog()
        guard let index = catalog.records.firstIndex(where: { $0.id == id }) else { throw RuntimeIssue("项目尚未登记") }
        let record = catalog.records[index]
        let snapshot = try record.grant.coordinated { root in
            guard try key(root) == record.directoryKey else { throw RuntimeIssue("目录已被替换，请重新选择项目") }
            return try ProjectFiles.snapshot(at: root)
        }
        let declared = snapshot.info.declaredID
        if let expected = record.declaredID, declared != expected { throw RuntimeIssue("runtime.json · 项目标识与登记记录不符") }
        if let declared, catalog.records.contains(where: { $0.id != id && $0.declaredID == declared }) {
            throw RuntimeIssue("runtime.json · 项目标识与另一个目录冲突")
        }
        if remember || record.name != snapshot.info.name || record.version != snapshot.info.version || record.declaredID != declared {
            catalog.records[index].declaredID = declared
            catalog.records[index].name = snapshot.info.name
            catalog.records[index].version = snapshot.info.version
            if remember { catalog.records[index].opened = Date(); catalog.last = id }
            try save(catalog)
        }
        return snapshot
    }

    func reconnect(_ id: UUID, url: URL) throws {
        var catalog = try catalog()
        guard let index = catalog.records.firstIndex(where: { $0.id == id }) else { throw RuntimeIssue("项目尚未登记") }
        let grant = try FolderGrant.selected(url)
        let identity = try grant.coordinated { try key($0) }
        guard identity == catalog.records[index].directoryKey else { throw RuntimeIssue("请选择原项目文件夹，所选目录的身份不同") }
        catalog.records[index].grant = grant
        try save(catalog)
    }

    func rename(_ record: ProjectRecord, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RuntimeIssue("项目名称不能为空") }
        try record.grant.coordinated(write: true) { root in
            guard try key(root) == record.directoryKey else { throw RuntimeIssue("目录身份发生变化") }
            try ProjectFiles.rename(name, at: root)
        }
        _ = try open(record.id, remember: false)
    }

    func forgetLast() throws { var value = try catalog(); value.last = nil; try save(value) }
}

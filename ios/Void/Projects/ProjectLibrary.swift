import Darwin
import Foundation

struct ProjectRecord: Codable, Identifiable {
    let id: UUID
    var grant: FolderGrant
    var directoryKey: String
    var declaredID: String?
    var name: String
    var version: String
    var opened: Date?
    var pendingTemplate: ProjectTemplate?
}

struct Catalog: Codable {
    var records: [ProjectRecord] = []
    var last: UUID?

    var recent: [ProjectRecord] {
        records.filter { $0.opened != nil }.sorted { ($0.opened ?? .distantPast) > ($1.opened ?? .distantPast) }
    }
}

actor ProjectLibrary {
    private let file: URL
    init(base: URL) { file = base.appendingPathComponent("projects.json") }

    func catalog() throws -> Catalog {
        let data: Data
        do { data = try Data(contentsOf:file) }
        catch {
            let issue = DirectoryIssue.reading(error,item:"项目登记文件")
            if issue.kind == .missing { return Catalog() }
            throw issue
        }
        do { return try JSONDecoder().decode(Catalog.self,from:data) }
        catch { throw DirectoryIssue(kind:.invalidJSON,item:"项目登记文件",underlying:error as NSError) }
    }

    private func save(_ catalog: Catalog) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(catalog).write(to: file, options: .atomic)
    }

    static func directoryKey(_ url: URL) throws -> String {
        guard try ProjectSourceReader().kind(url,"登记目录") == .directory else { throw DirectoryIssue(kind:.wrongType,item:"登记目录") }
        let attributes = Result { try FileManager.default.attributesOfItem(atPath:url.path) }
        if case let .success(attrs) = attributes, let device = attrs[.systemNumber] as? NSNumber,
           let inode = attrs[.systemFileNumber] as? NSNumber, inode.uint64Value != 0 {
            return device.stringValue + "/" + inode.stringValue
        }
        var item = stat()
        if lstat(url.path,&item) == 0, item.st_ino != 0 { return String(item.st_dev) + "/" + String(item.st_ino) }
        let values = try url.resourceValues(forKeys:[.documentIdentifierKey,.volumeUUIDStringKey])
        if let document = values.documentIdentifier, document > 0, let volume = values.volumeUUIDString {
            return "document/" + volume + "/" + String(document)
        }
        if case let .failure(error) = attributes { throw DirectoryIssue.reading(error,item:"登记目录") }
        throw RuntimeIssue("文件服务商未提供可验证的目录标识")
    }

    private struct Observation {
        let grant: FolderGrant
        let key: String
        let snapshot: SourceSnapshot
        let sameLocations: Set<UUID>
    }

    private static func inspect(_ original: FolderGrant, known: [ProjectRecord], incomplete: Bool, trace: DirectoryTrace?, io: DirectoryIO,
                                metadataOnly: Bool = false) throws -> Observation {
        let grant = try DirectoryTrace.measuring(trace,"grant","恢复登记位置") { try original.refreshed() }
        let (key, snapshot) = try grant.coordinated(io:io,trace:trace) { root in
            trace?.event("scan.begin")
            do {
                let key = try directoryKey(root)
                let snapshot: SourceSnapshot
                if metadataOnly {
                    let (info,files) = try ProjectSourceReader().configuration(root)
                    snapshot = SourceSnapshot(info:info,files:files,revision:"")
                } else { snapshot = try ProjectFiles.snapshot(at:root,allowMissingEntry:incomplete,trace:trace,io:io) }
                trace?.event("scan.end","OK")
                return (key,snapshot)
            } catch { trace?.event("scan.end","失败",error:error); throw error }
        }
        var matches = Set<UUID>()
        for record in known where record.directoryKey != key {
            try io.check()
            if record.grant.sameLocation(as:grant) { matches.insert(record.id) }
        }
        return Observation(grant:grant,key:key,snapshot:snapshot,sameLocations:matches)
    }

    private static func matched(_ observed: Observation, _ record: ProjectRecord) throws {
        let info = observed.snapshot.info
        if let expected = record.declaredID, expected != info.declaredID { throw DirectoryIssue(kind:.identity,item:"runtime.json") }
        if record.directoryKey == observed.key { return }
        guard observed.sameLocations.contains(record.id), let expected = record.declaredID,
              observed.snapshot.files["runtime.json"] != nil, info.runtimeID == expected else {
            throw DirectoryIssue(kind:.identity,item:"登记目录")
        }
    }

    private func register(_ observations: [Observation], template: ProjectTemplate? = nil, commit: DirectoryCommit? = nil) throws -> [ProjectRecord] {
        try Task.checkCancellation()
        var catalog = try catalog()
        var found: [ProjectRecord] = []
        for o in observations {
            let info = o.snapshot.info
            let existing = catalog.records.first { $0.directoryKey == o.key || o.sameLocations.contains($0.id) || $0.grant == o.grant }
            if let id = info.declaredID, catalog.records.contains(where:{ $0.declaredID == id && $0.id != existing?.id }) {
                throw RuntimeIssue("另一目录已登记相同的项目 id，原登记已保留")
            }
            var record: ProjectRecord
            if var prior = existing {
                try Self.matched(o,prior)
                prior.grant = o.grant; prior.directoryKey = o.key
                prior.declaredID = info.declaredID; prior.name = info.name; prior.version = info.version
                if prior.opened == nil { prior.opened = Date() }
                record = prior
            } else {
                record = ProjectRecord(id:UUID(),grant:o.grant,directoryKey:o.key,declaredID:info.declaredID,
                    name:info.name,version:info.version,opened:Date(),pendingTemplate:template)
            }
            if let index = catalog.records.firstIndex(where:{$0.id == record.id}) { catalog.records[index] = record }
            else { catalog.records.append(record) }
            found.append(record)
        }
        try Task.checkCancellation()
        try commit?.begin()
        try save(catalog)
        return found
    }

    func create(name: String, parent: URL?, template: ProjectTemplate = .swiftUI, trace: DirectoryTrace? = nil, commit: DirectoryCommit? = nil) async throws -> ProjectRecord {
        let observed = try await DirectoryIO.run(trace:trace) { io -> Observation in
            let parent = try parent.map { try FolderGrant.selected($0,trace:trace) } ?? FolderGrant(bookmark:nil,child:"")
            var child = parent; child.child = name
            return try parent.coordinated(write:true,io:io,trace:trace) { root in
                var prepared: Observation?
                _ = try ProjectFiles.create(name,in:root,template:template,io:io) { staging in
                    trace?.event("scan.begin")
                    do {
                        let snapshot = try ProjectFiles.snapshot(at:staging,trace:trace,io:io)
                        prepared = Observation(grant:child,key:try Self.directoryKey(staging),snapshot:snapshot,sameLocations:[])
                        trace?.event("scan.end","OK")
                    } catch { trace?.event("scan.end","失败",error:error); throw error }
                    try io.check()
                    try commit?.begin()
                }
                guard let prepared else { throw DirectoryIssue(kind:.provider,item:"创建项目") }
                return prepared
            }
        }
        return try register([observed],template:template,commit:commit)[0]
    }

    private static func children(of grant: FolderGrant, localRoot: Bool, trace: DirectoryTrace?, io: DirectoryIO) throws -> [FolderGrant] {
        try grant.coordinated(io:io,trace:trace) { root in
            let reader = ProjectSourceReader()
            func hasProject(_ url: URL) throws -> Bool {
                if try reader.optionalKind(url.appendingPathComponent("runtime.json"),"runtime.json") != nil { return true }
                return try reader.optionalKind(url.appendingPathComponent("app"),"app") != nil
            }
            if !localRoot, try hasProject(root) { return [grant] }
            var found: [FolderGrant] = []
            for child in try reader.list(root,"项目列表",trace:trace,io:io).sorted(by:{$0.lastPathComponent < $1.lastPathComponent}) {
                try io.check()
                guard !["data","logs"].contains(child.lastPathComponent) else { continue }
                let type: ProjectSourceReader.Kind?
                do { type = try reader.optionalKind(child,"子目录") }
                catch let error as DirectoryIssue where error.kind == .link { continue }
                guard type == .directory, try hasProject(child) else { continue }
                var item = grant; item.child = child.lastPathComponent; found.append(item)
            }
            guard !found.isEmpty else { throw DirectoryIssue(kind:.noProjects,item:"项目列表") }
            return found
        }
    }

    func discover(_ url: URL, localRoot: Bool = false, trace: DirectoryTrace? = nil, commit: DirectoryCommit? = nil) async throws -> [ProjectRecord] {
        let known = try catalog().records
        let observations = try await DirectoryIO.run(trace:trace) { io in
            let grant = try FolderGrant.selected(url,trace:trace)
            if localRoot, grant.bookmark != nil || !grant.sameLocation(as:FolderGrant(bookmark:nil,child:"")) {
                throw DirectoryIssue(kind:.outside,item:"本机项目")
            }
            let choices = try DirectoryTrace.measuring(trace,"scan","发现项目") {
                try Self.children(of:grant,localRoot:localRoot,trace:trace,io:io)
            }
            return try choices.map {
                try Self.inspect($0,known:known,incomplete:true,trace:trace,io:io)
            }
        }
        return try register(observations,commit:commit)
    }

    private static func locateLocal(_ record: ProjectRecord, trace: DirectoryTrace?, io: DirectoryIO, metadataOnly: Bool) throws -> Observation? {
        let local = FolderGrant(bookmark:nil,child:"")
        let match: FolderGrant? = try local.coordinated(io:io,trace:trace) { root in
            let reader = ProjectSourceReader()
            for url in try reader.list(root,"本机项目",trace:trace,io:io) {
                try io.check()
                guard (try? directoryKey(url)) == record.directoryKey else { continue }
                return FolderGrant(bookmark:nil,child:url.lastPathComponent)
            }
            return nil
        }
        guard let match else { return nil }
        return try inspect(match,known:[record],incomplete:metadataOnly,trace:trace,io:io,metadataOnly:metadataOnly)
    }

    func open(_ id: UUID, remember: Bool, trace: DirectoryTrace? = nil) async throws -> SourceSnapshot {
        guard let record = try catalog().records.first(where:{ $0.id == id && $0.opened != nil }) else { throw RuntimeIssue("项目已从最近记录移除") }
        let observed = try await Self.readRegistered(record,trace:trace,metadataOnly:false)
        try updateRecord(observed,record:record,updateLast:remember)
        return observed.snapshot
    }

    private static func readRegistered(_ record: ProjectRecord, trace: DirectoryTrace?, metadataOnly: Bool) async throws -> Observation {
        try await DirectoryIO.run(trace:trace) { io in
            do { return try inspect(record.grant,known:[record],incomplete:metadataOnly,trace:trace,io:io,metadataOnly:metadataOnly) }
            catch let error as DirectoryIssue where ["登记目录","外部目录授权","原目录书签","目录协调"].contains(error.item) {
                guard let local = try locateLocal(record,trace:trace,io:io,metadataOnly:metadataOnly) else { throw error }
                trace?.event("grant.recovered","Documents"); return local
            }
        }
    }

    private func updateRecord(_ observed: Observation, record: ProjectRecord, updateLast: Bool) throws {
        try Task.checkCancellation()
        let id = record.id
        var catalog = try catalog()
        guard let index = catalog.records.firstIndex(where:{ $0.id == id && $0.opened != nil }),
              catalog.records[index].grant == record.grant || catalog.records[index].grant == observed.grant else { throw CancellationError() }
        try Self.matched(observed,catalog.records[index])
        let info = observed.snapshot.info
        if let declared = info.declaredID, catalog.records.contains(where:{ $0.id != id && $0.declaredID == declared }) {
            throw DirectoryIssue(kind:.identity,item:"runtime.json")
        }
        if updateLast || record.name != info.name || record.version != info.version || record.declaredID != info.declaredID ||
            record.grant != observed.grant || record.directoryKey != observed.key {
            catalog.records[index].grant = observed.grant; catalog.records[index].directoryKey = observed.key
            catalog.records[index].declaredID = info.declaredID; catalog.records[index].name = info.name; catalog.records[index].version = info.version
            if updateLast { catalog.records[index].opened = Date(); catalog.last = id }
            try save(catalog)
        }
    }

    func reconnect(_ id: UUID, url: URL, trace: DirectoryTrace? = nil, commit: DirectoryCommit? = nil) async throws {
        guard let record = try catalog().records.first(where:{ $0.id == id }) else { throw RuntimeIssue("项目尚未登记") }
        let observed = try await DirectoryIO.run(trace:trace) { io in
            try Self.inspect(FolderGrant.selected(url,trace:trace),known:[record],incomplete:true,trace:trace,io:io)
        }
        try Task.checkCancellation()
        try Self.matched(observed,record)
        guard try catalog().records.contains(where:{ $0.id == id && $0.opened != nil && $0.grant == record.grant }) else { throw CancellationError() }
        _ = try register([observed],commit:commit)
    }

    func rename(_ record: ProjectRecord, name: String) async throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw RuntimeIssue("项目名称不能为空") }
        try await DirectoryIO.run { io in
            try record.grant.coordinated(write:true,io:io) { root in
                guard try Self.directoryKey(root) == record.directoryKey else { throw DirectoryIssue(kind:.identity,item:"目录") }
                try io.check()
                try ProjectFiles.rename(name,at:root)
            }
        }
        _ = try await open(record.id,remember:false)
    }

    func forgetLast() throws { var value = try catalog(); value.last = nil; try save(value) }

    @discardableResult
    func selectWorkspace(_ id: UUID) async throws -> [String] {
        guard let record = try catalog().recent.first(where:{$0.id == id}) else { throw RuntimeIssue("项目已从最近记录移除") }
        let trace = DirectoryTrace("workspace")
        trace.event("workspace.begin")
        let observed = try await Self.readRegistered(record,trace:trace,metadataOnly:true)
        try updateRecord(observed,record:record,updateLast:true)
        return observed.snapshot.info.permissions
    }

    func finishFirstPreview(_ id: UUID) throws {
        var value = try catalog()
        guard let index = value.records.firstIndex(where: { $0.id == id }), value.records[index].pendingTemplate != nil else { return }
        value.records[index].pendingTemplate = nil
        try save(value)
    }

    func removeRecent(_ id: UUID) throws {
        var value = try catalog()
        guard let index = value.records.firstIndex(where: { $0.id == id }) else { return }
        value.records[index].opened = nil
        if value.last == id { value.last = nil }
        try save(value)
    }
}

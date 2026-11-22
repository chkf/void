import Darwin
import Foundation

struct ProjectRecord: Codable, Identifiable {
    let id: UUID
    var grant: FolderGrant
    var directoryKey: String
    var declaredID: String?
    var name: String
    var version: String
    var pendingTemplate: ProjectTemplate?
    var isListed = true
    var github: GitHubCheckout?

    private enum CodingKeys: String, CodingKey {
        case id, grant, directoryKey, declaredID, name, version, pendingTemplate, isListed, github
    }
}

extension ProjectRecord {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(UUID.self, forKey: .id)
        grant = try fields.decode(FolderGrant.self, forKey: .grant)
        directoryKey = try fields.decode(String.self, forKey: .directoryKey)
        declaredID = try fields.decodeIfPresent(String.self, forKey: .declaredID)
        name = try fields.decode(String.self, forKey: .name)
        version = try fields.decode(String.self, forKey: .version)
        pendingTemplate = try fields.decodeIfPresent(ProjectTemplate.self, forKey: .pendingTemplate)
        github = try fields.decodeIfPresent(GitHubCheckout.self, forKey: .github)
        if let listed = try fields.decodeIfPresent(Bool.self, forKey: .isListed) {
            isListed = listed
        } else {
            // The old catalog identified a removed record by omitting its last-opened date.
            enum LegacyKey: String, CodingKey { case opened }
            let legacy = try decoder.container(keyedBy: LegacyKey.self)
            isListed = try legacy.contains(.opened) && !legacy.decodeNil(forKey: .opened)
        }
    }
}

struct Catalog: Codable {
    var schemaVersion: Int? = 2
    var records: [ProjectRecord] = []
    var last: UUID?
    // A clone or pull records the next identity before publishing its working directory.
    var pendingInstall: ProjectRecord?

    var projects: [ProjectRecord] {
        records.filter(\.isListed).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }
}

actor ProjectLibrary {
    private let file: URL
    private var pulling = Set<UUID>()
    init(base: URL) { file = base.appendingPathComponent("projects.json") }

    func catalog() throws -> Catalog {
        let data: Data
        do { data = try Data(contentsOf:file) }
        catch {
            let issue = DirectoryIssue.reading(error,item:"项目登记文件")
            if issue.kind == .missing { return Catalog() }
            throw issue
        }
        var result: Catalog
        do { result = try JSONDecoder().decode(Catalog.self,from:data) }
        catch { throw DirectoryIssue(kind:.invalidJSON,item:"项目登记文件",underlying:error as NSError) }
        var needsSave = result.schemaVersion == nil
        if var next = result.pendingInstall {
            let index = result.records.firstIndex(where: { $0.id == next.id })
            let currentKey = try? next.grant.withRoot(Self.directoryKey)
            var installed = currentKey == next.directoryKey
            if !installed && (index == nil || currentKey != index.map { result.records[$0].directoryKey }) {
                // Files may have renamed the newly published folder before the host restarted.
                let children = try FileManager.default.contentsOfDirectory(at: FolderGrant.documents,
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                if let moved = children.first(where: { (try? Self.directoryKey($0)) == next.directoryKey }) {
                    next.grant = FolderGrant(bookmark: nil, child: moved.lastPathComponent)
                    installed = true
                }
            }
            if installed {
                if let index { result.records[index] = next }
                else { result.records.append(next) }
            } else if index == nil {
                try? FileManager.default.removeItem(at: gitDatabase(next.id).deletingLastPathComponent())
            }
            result.pendingInstall = nil
            needsSave = true
        }
        if needsSave { result.schemaVersion = 2; try save(result) }
        return result
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

    private enum Contents { case configuration, sources, fingerprint }

    private struct Observation {
        let grant: FolderGrant
        let key: String
        let snapshot: SourceSnapshot
        let sameLocations: Set<UUID>
    }

    // Keep the working copies off the project list until every selected project is valid.
    private final class ImportStaging {
        let directory: URL
        var originals: [String: Observation] = [:]

        init() throws {
            directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: FolderGrant.documents, create: true)
        }
        deinit { try? FileManager.default.removeItem(at: directory) }

        func publish(_ projects: [Observation], saveCatalog: () throws -> Void) throws {
            let manager = FileManager.default
            for project in projects {
                let name = project.grant.child
                if manager.fileExists(atPath: FolderGrant.documents.appendingPathComponent(name).path) {
                    throw RuntimeIssue("void 文稿中已有「" + name + "」，请更改文件夹名称后再导入")
                }
            }
            var published: [Observation] = []
            do {
                for project in projects {
                    let name = project.grant.child
                    let target = FolderGrant.documents.appendingPathComponent(name)
                    try manager.moveItem(at: directory.appendingPathComponent(name), to: target)
                    published.append(project)
                }
                try saveCatalog()
            } catch {
                for project in published.reversed() {
                    let name = project.grant.child
                    let target = FolderGrant.documents.appendingPathComponent(name)
                    if (try? ProjectLibrary.directoryKey(target)) == project.key {
                        try? manager.moveItem(at: target, to: directory.appendingPathComponent(name))
                    }
                }
                throw error
            }
        }
    }

    private static func inspect(_ original: FolderGrant, known: [ProjectRecord], incomplete: Bool, trace: DirectoryTrace?, io: DirectoryIO,
                                contents: Contents = .sources) throws -> Observation {
        let grant = try DirectoryTrace.measuring(trace,"grant","恢复登记位置") { try original.refreshed() }
        let (key, snapshot) = try grant.coordinated(io:io,trace:trace) { root in
            trace?.event("scan.begin")
            do {
                let key = try directoryKey(root)
                let snapshot: SourceSnapshot
                let reader = ProjectSourceReader()
                if contents == .configuration {
                    let (info,files) = try reader.configuration(root,io:io)
                    snapshot = SourceSnapshot(info:info,files:files,revision:"")
                    trace?.event("scan.configuration")
                } else {
                    snapshot = try reader.snapshot(root,allowMissingEntry:incomplete,trace:trace,io:io,retainingSources:contents == .sources)
                }
                trace?.event("scan.end","OK")
                return (key,snapshot)
            } catch { trace?.event("scan.end","失败",error:error); throw error }
        }
        return try observation(grant: grant, key: key, snapshot: snapshot, known: known, io: io)
    }

    private static func observation(grant: FolderGrant, key: String, snapshot: SourceSnapshot,
                                    known: [ProjectRecord], io: DirectoryIO) throws -> Observation {
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

    private func register(_ observations: [Observation], template: ProjectTemplate? = nil, commit: DirectoryCommit? = nil,
                          onlyNew: Bool = false, staging: ImportStaging? = nil,
                          git: (id: UUID, source: GitHubCheckout)? = nil) throws -> [ProjectRecord] {
        try Task.checkCancellation()
        let originalCatalog = try catalog()
        var catalog = originalCatalog
        var found: [ProjectRecord] = []
        for o in observations {
            let info = o.snapshot.info
            let original = staging?.originals[o.grant.child] ?? o
            let existing = catalog.records.first { $0.directoryKey == original.key || original.sameLocations.contains($0.id) || $0.grant == original.grant }
            if git != nil, existing != nil { throw RuntimeIssue("此目录已登记，请从项目列表打开或拉取更新") }
            if onlyNew {
                let location = FolderGrant.documents.appendingPathComponent(o.grant.child)
                guard existing == nil, (try? Self.directoryKey(location)) == o.key else { continue }
            }
            if let id = info.declaredID, catalog.records.contains(where:{ $0.declaredID == id && $0.id != existing?.id }) {
                if onlyNew { continue }
                throw RuntimeIssue("另一目录已登记相同的项目 id，原登记已保留")
            }
            if staging != nil, catalog.records.contains(where: {
                $0.id != existing?.id && $0.grant.bookmark == nil && $0.grant.sameLocation(as: o.grant)
            }) { throw RuntimeIssue("void 文稿中的同名位置已登记其他项目") }
            var record: ProjectRecord
            if var prior = existing {
                try Self.matched(original,prior)
                prior.grant = o.grant; prior.directoryKey = o.key
                prior.declaredID = info.declaredID; prior.name = info.name; prior.version = info.version
                if let template { prior.pendingTemplate = template }
                prior.isListed = true
                record = prior
            } else {
                record = ProjectRecord(id:git?.id ?? UUID(),grant:o.grant,directoryKey:o.key,declaredID:info.declaredID,
                    name:info.name,version:info.version,pendingTemplate:template,github:git?.source)
            }
            if let index = catalog.records.firstIndex(where:{$0.id == record.id}) { catalog.records[index] = record }
            else { catalog.records.append(record) }
            found.append(record)
        }
        try Task.checkCancellation()
        guard !found.isEmpty else { return [] }
        try commit?.begin()
        if template != nil, let created = found.first { catalog.last = created.id }
        if let staging {
            if git != nil {
                var pending = originalCatalog
                pending.pendingInstall = found[0]
                try save(pending)
            }
            try staging.publish(observations) { try save(catalog) }
        }
        else { try save(catalog) }
        return found
    }

    // Only inspect the configurations of immediate child folders. Existing records include
    // hidden projects, which an automatic refresh must not add back.
    func recognizeLocalProjects() async throws -> Bool {
        let known = try catalog().records
        let keys = Set(known.map(\.directoryKey))
        let localRecords = known.filter { $0.grant.bookmark == nil }
        let observations = try await DirectoryIO.run { io in
            let documents = FolderGrant(bookmark: nil, child: "")
            return try documents.coordinated(io: io) { root -> [Observation] in
                let reader = ProjectSourceReader()
                let folders = try reader.list(root, "void 文稿", io: io).sorted { $0.lastPathComponent < $1.lastPathComponent }
                return try folders.compactMap { url in
                    try io.check()
                    guard let key = try? Self.directoryKey(url), !keys.contains(key),
                          let (info, files) = try? reader.configuration(url, io: io) else { return nil }
                    let grant = FolderGrant(bookmark: nil, child: url.lastPathComponent)
                    let snapshot = SourceSnapshot(info: info, files: files, revision: "")
                    return try Self.observation(grant: grant, key: key, snapshot: snapshot, known: localRecords, io: io)
                }
            }
        }
        guard !observations.isEmpty else { return false }
        let added = try register(observations, onlyNew: true)
        return !added.isEmpty
    }

    func create(name: String, parent: URL?, trace: DirectoryTrace? = nil, commit: DirectoryCommit? = nil) async throws -> ProjectRecord {
        let observed = try await DirectoryIO.run(trace:trace) { io -> Observation in
            let parent = try parent.map { try FolderGrant.selected($0,trace:trace) } ?? FolderGrant(bookmark:nil,child:"")
            var child = parent; child.child = name
            return try parent.coordinated(write:true,io:io,trace:trace) { root in
                var prepared: Observation?
                _ = try ProjectFiles.create(name,in:root,io:io) { staging in
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
        return try register([observed],template:.tsx,commit:commit)[0]
    }

    private static func children(of grant: FolderGrant, trace: DirectoryTrace?, io: DirectoryIO) throws -> [FolderGrant] {
        try grant.coordinated(io:io,trace:trace) { root in
            let reader = ProjectSourceReader()
            func hasProject(_ url: URL) throws -> Bool {
                if try reader.optionalKind(url.appendingPathComponent("runtime.json"),"runtime.json") != nil { return true }
                return try reader.optionalKind(url.appendingPathComponent("app"),"app") != nil
            }
            if try hasProject(root) { return [grant] }
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

    func discover(_ url: URL, trace: DirectoryTrace? = nil, commit: DirectoryCommit? = nil) async throws -> [ProjectRecord] {
        let (grant, choices) = try await DirectoryIO.run(trace:trace) { io in
            let grant = try FolderGrant.selected(url,trace:trace)
            let choices = try DirectoryTrace.measuring(trace,"scan","发现项目") {
                try Self.children(of:grant,trace:trace,io:io)
            }
            return (grant, choices)
        }
        if grant.bookmark != nil { return try await copyIntoDocuments(choices, trace: trace, commit: commit) }
        let known = try catalog().records
        let observations = try await DirectoryIO.run(trace:trace) { io in
            try choices.map {
                try Self.inspect($0,known:known,incomplete:true,trace:trace,io:io,contents:.fingerprint)
            }
        }
        return try register(observations,commit:commit)
    }

    func copyIntoDocuments(_ choices: [FolderGrant], trace: DirectoryTrace? = nil, commit: DirectoryCommit? = nil) async throws -> [ProjectRecord] {
        let known = try catalog().records
        let (staging, projects) = try await DirectoryIO.run(trace: trace) { io in
            let staging = try ImportStaging()
            let projects = try choices.map { grant in
                try grant.coordinated(io: io, trace: trace) { source -> Observation in
                    try io.check()
                    let name = source.lastPathComponent
                    guard ProjectFiles.component(name),
                          !ProjectSourceReader.canonical(staging.directory).starts(with: ProjectSourceReader.canonical(source)) else {
                        throw DirectoryIssue(kind: .outside, item: "导入目录")
                    }
                    let copy = staging.directory.appendingPathComponent(name, isDirectory: true)
                    trace?.event("import.copy", DirectoryTrace.leaf(source))
                    try FileManager.default.copyItem(at: source, to: copy)
                    try io.check()
                    let snapshot = try ProjectSourceReader().snapshot(copy, allowMissingEntry: true, trace: trace, io: io, retainingSources: false)
                    staging.originals[name] = try Self.observation(grant: grant, key: Self.directoryKey(source),
                                                                   snapshot: snapshot, known: known, io: io)
                    return Observation(grant: FolderGrant(bookmark: nil, child: name), key: try Self.directoryKey(copy),
                                       snapshot: snapshot, sameLocations: [])
                }
            }
            return (staging, projects)
        }
        return try register(projects, commit: commit, staging: staging)
    }

    private func gitDatabase(_ id: UUID) -> URL {
        file.deletingLastPathComponent().appendingPathComponent("Repositories")
            .appendingPathComponent(id.uuidString).appendingPathComponent(".git")
    }

    func clone(_ source: GitHubRepository,
               transfer: @escaping @Sendable (String, URL) throws -> String = { try ProjectGit.clone($0, to: $1) }) async throws -> ProjectRecord {
        let id = UUID()
        let database = gitDatabase(id)
        let manager = FileManager.default
        let staging = try ImportStaging()
        let copy = staging.directory.appendingPathComponent(source.name)
        let grant = FolderGrant(bookmark: nil, child: source.name)
        guard !manager.fileExists(atPath: FolderGrant.documents.appendingPathComponent(source.name).path) else {
            throw RuntimeIssue("void 文稿中已有「" + source.name + "」，请选择已有项目")
        }
        let (commit, observation) = try await Task.detached(priority: .userInitiated) {
            let commit = try transfer(source.address, copy)
            let snapshot = try ProjectSourceReader().snapshot(copy, allowMissingEntry: false, retainingSources: false)
            return (commit, Observation(grant: grant, key: try Self.directoryKey(copy), snapshot: snapshot, sameLocations: []))
        }.value
        try Task.checkCancellation()
        let privateFolder = database.deletingLastPathComponent()
        try manager.createDirectory(at: privateFolder, withIntermediateDirectories: true)
        do {
            try manager.moveItem(at: copy.appendingPathComponent(".git"), to: database)
            let source = GitHubCheckout(address: source.address, commit: commit)
            return try register([observation], staging: staging, git: (id, source))[0]
        } catch {
            if (try? grant.withRoot(Self.directoryKey)) != observation.key { try? manager.removeItem(at: privateFolder) }
            throw error
        }
    }

    func pull(_ id: UUID) async throws -> ProjectRecord {
        guard let record = try catalog().projects.first(where: { $0.id == id }), let source = record.github else {
            throw RuntimeIssue("项目没有关联 GitHub 仓库")
        }
        guard pulling.insert(id).inserted else { throw RuntimeIssue("正在拉取此项目") }
        defer { pulling.remove(id) }
        let database = gitDatabase(id)
        let target = try await Task.detached(priority: .userInitiated) {
            try ProjectGit.fetch(source.commit, database: database)
        }.value
        try Task.checkCancellation()
        let located = try await Self.readRegistered(record, trace: nil, contents: .configuration)
        try updateRecord(located, record: record, updateLast: false)
        var catalog = try catalog()
        guard let index = catalog.records.firstIndex(where: { $0.id == id && $0.isListed }),
              catalog.records[index].github?.commit == source.commit else { throw CancellationError() }
        let live = catalog.records[index]
        guard target != source.commit else { return live }
        let staging = try ImportStaging()
        return try live.grant.coordinated(write: true, writingOptions: .forReplacing) { root in
            guard try Self.directoryKey(root) == live.directoryKey else { throw DirectoryIssue(kind: .identity, item: "登记目录") }
            let candidate = staging.directory.appendingPathComponent(root.lastPathComponent)
            try FileManager.default.copyItem(at: root, to: candidate)
            try ProjectGit.checkout(target, from: source.commit, database: database, at: candidate)
            let snapshot = try ProjectSourceReader().snapshot(candidate, allowMissingEntry: false, retainingSources: false)
            let info = snapshot.info
            if let expected = live.declaredID, expected != info.declaredID { throw DirectoryIssue(kind: .identity, item: "项目 id") }
            if let declared = info.declaredID, catalog.records.contains(where: { $0.id != id && $0.declaredID == declared }) {
                throw RuntimeIssue("另一目录已登记相同的项目 id")
            }
            var next = live
            next.directoryKey = try Self.directoryKey(candidate)
            next.name = info.name
            next.version = info.version
            next.declaredID = info.declaredID
            next.github?.commit = target
            try Task.checkCancellation()
            catalog.pendingInstall = next
            try save(catalog)
            guard renamex_np(candidate.path, root.path, UInt32(RENAME_SWAP)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            catalog.records[index] = next
            catalog.pendingInstall = nil
            try save(catalog)
            return next
        }
    }

    private static func locateLocal(_ record: ProjectRecord, trace: DirectoryTrace?, io: DirectoryIO, contents: Contents) throws -> Observation? {
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
        return try inspect(match,known:[record],incomplete:contents == .configuration,trace:trace,io:io,contents:contents)
    }

    func open(_ id: UUID, remember: Bool, trace: DirectoryTrace? = nil) async throws -> SourceSnapshot {
        guard let record = try catalog().records.first(where:{ $0.id == id && $0.isListed }) else { throw RuntimeIssue("项目已从列表移除") }
        let observed = try await Self.readRegistered(record,trace:trace,contents:.sources)
        try updateRecord(observed,record:record,updateLast:remember)
        return observed.snapshot
    }

    func revision(_ id: UUID, trace: DirectoryTrace? = nil) async throws -> String {
        guard let record = try catalog().projects.first(where:{ $0.id == id }) else { throw RuntimeIssue("项目已从列表移除") }
        let observed = try await Self.readRegistered(record,trace:trace,contents:.fingerprint)
        try updateRecord(observed,record:record,updateLast:false)
        return observed.snapshot.revision
    }

    private static func readRegistered(_ record: ProjectRecord, trace: DirectoryTrace?, contents: Contents) async throws -> Observation {
        try await DirectoryIO.run(trace:trace) { io in
            do { return try inspect(record.grant,known:[record],incomplete:contents == .configuration,trace:trace,io:io,contents:contents) }
            catch let error as DirectoryIssue where ["登记目录","外部目录授权","原目录书签","目录协调"].contains(error.item) {
                guard let local = try locateLocal(record,trace:trace,io:io,contents:contents) else { throw error }
                trace?.event("grant.recovered","Documents"); return local
            }
        }
    }

    private func updateRecord(_ observed: Observation, record: ProjectRecord, updateLast: Bool) throws {
        try Task.checkCancellation()
        let id = record.id
        var catalog = try catalog()
        guard let index = catalog.records.firstIndex(where:{ $0.id == id && $0.isListed }),
              catalog.records[index].directoryKey == record.directoryKey || catalog.records[index].directoryKey == observed.key,
              catalog.records[index].grant == record.grant || catalog.records[index].grant == observed.grant else { throw CancellationError() }
        try Self.matched(observed,catalog.records[index])
        let info = observed.snapshot.info
        if let declared = info.declaredID, catalog.records.contains(where:{ $0.id != id && $0.declaredID == declared }) {
            throw DirectoryIssue(kind:.identity,item:"runtime.json")
        }
        if (updateLast && catalog.last != id) || record.name != info.name || record.version != info.version || record.declaredID != info.declaredID ||
            record.grant != observed.grant || record.directoryKey != observed.key {
            catalog.records[index].grant = observed.grant; catalog.records[index].directoryKey = observed.key
            catalog.records[index].declaredID = info.declaredID; catalog.records[index].name = info.name; catalog.records[index].version = info.version
            if updateLast { catalog.last = id }
            try save(catalog)
        }
    }

    func reconnect(_ id: UUID, url: URL, trace: DirectoryTrace? = nil, commit: DirectoryCommit? = nil) async throws {
        guard let record = try catalog().records.first(where:{ $0.id == id }) else { throw RuntimeIssue("项目尚未登记") }
        let observed = try await DirectoryIO.run(trace:trace) { io in
            try Self.inspect(FolderGrant.selected(url,trace:trace),known:[record],incomplete:true,trace:trace,io:io,contents:.fingerprint)
        }
        try Task.checkCancellation()
        try Self.matched(observed,record)
        guard try catalog().records.contains(where:{ $0.id == id && $0.isListed && $0.grant == record.grant }) else { throw CancellationError() }
        _ = try register([observed],commit:commit)
    }

    func rename(_ id: UUID, name: String) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RuntimeIssue("项目名称不能为空") }
        guard let record = try catalog().projects.first(where: { $0.id == id }) else { throw RuntimeIssue("项目已从列表移除") }
        let located = try await Self.readRegistered(record, trace: nil, contents: .configuration)
        try Self.matched(located, record)
        let updated = try await DirectoryIO.run { io -> Observation in
            try located.grant.coordinated(write: true, io: io) { root in
                guard try Self.directoryKey(root) == located.key else { throw DirectoryIssue(kind: .identity, item: "目录") }
                let (info, configuration) = try ProjectSourceReader().configuration(root, io: io)
                guard info.declaredID == located.snapshot.info.declaredID else { throw DirectoryIssue(kind: .identity, item: "runtime.json") }
                try io.check()
                let manifest = "app/manifest.json"
                var files = configuration
                files[manifest] = try ProjectFiles.rename(name, at: root, manifestData: configuration[manifest])
                let renamed = try ProjectFiles.metadata(files, folderName: root.lastPathComponent)
                return Observation(grant: located.grant, key: located.key,
                    snapshot: SourceSnapshot(info: renamed, files: files, revision: ""), sameLocations: located.sameLocations)
            }
        }
        try updateRecord(updated, record: record, updateLast: false)
    }

    func forgetLast() throws {
        var value = try catalog()
        if value.last != nil { value.last = nil; try save(value) }
    }

    func details(_ id: UUID) async throws -> ProjectRecord {
        guard let record = try catalog().projects.first(where: { $0.id == id }) else { throw RuntimeIssue("项目已从列表移除") }
        let observed = try await Self.readRegistered(record, trace: nil, contents: .configuration)
        try updateRecord(observed, record: record, updateLast: false)
        guard let updated = try catalog().records.first(where: { $0.id == id }) else { throw CancellationError() }
        return updated
    }

    @discardableResult
    func selectWorkspace(_ id: UUID) async throws -> [String] {
        guard let record = try catalog().projects.first(where:{$0.id == id}) else { throw RuntimeIssue("项目已从列表移除") }
        let trace = DirectoryTrace("workspace")
        trace.event("workspace.begin")
        let observed = try await Self.readRegistered(record,trace:trace,contents:.configuration)
        try updateRecord(observed,record:record,updateLast:true)
        return observed.snapshot.info.permissions
    }

    func finishFirstPreview(_ id: UUID) throws {
        var value = try catalog()
        guard let index = value.records.firstIndex(where: { $0.id == id }), value.records[index].pendingTemplate != nil else { return }
        value.records[index].pendingTemplate = nil
        try save(value)
    }

    func removeFromList(_ id: UUID) throws {
        var value = try catalog()
        guard let index = value.records.firstIndex(where: { $0.id == id }) else { return }
        value.records[index].isListed = false
        if value.last == id { value.last = nil }
        try save(value)
    }
}

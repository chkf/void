import Foundation

struct ProjectSourceReader {
    enum Kind { case directory, file }
    var children: (URL) throws -> [URL] = { try FileManager.default.contentsOfDirectory(at:$0,includingPropertiesForKeys:nil) }
    var bytes: (URL) throws -> Data = { try Data(contentsOf:$0) }
    struct Traits {
        var directory: Bool?
        var file: Bool?
        var link: Bool?
        var pendingDownload = false
    }
    var metadata: (URL) throws -> Traits = {
        let value = try $0.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey,.ubiquitousItemDownloadingStatusKey])
        return Traits(directory:value.isDirectory,file:value.isRegularFile,link:value.isSymbolicLink,
                     pendingDownload:value.ubiquitousItemDownloadingStatus == .notDownloaded)
    }

    static func canonical(_ url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path.split(separator:"/").map(String.init)
    }
    func kind(_ url: URL, _ key: String) throws -> Kind {
        do {
            let values = try metadata(url)
            if values.link == true { throw DirectoryIssue(kind:.link,item:key) }
            if values.pendingDownload {
                try? FileManager.default.startDownloadingUbiquitousItem(at:url)
                throw DirectoryIssue(kind:.pendingDownload,item:key)
            }
            if values.link == false {
                if values.directory == true { return .directory }
                if values.file == true { return .file }
            }
            // Some providers omit URL resource type flags. Stat the item itself, without following its final link.
            let type = try FileManager.default.attributesOfItem(atPath:url.path)[.type] as? FileAttributeType
            switch type {
            case .typeRegular: return .file
            case .typeDirectory: return .directory
            case .typeSymbolicLink: throw DirectoryIssue(kind:.link,item:key)
            default: throw DirectoryIssue(kind:.wrongType,item:key)
            }
        } catch {
            let failure = DirectoryIssue.reading(error,item:key)
            if failure.kind == .missing {
                let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
                if FileManager.default.isUbiquitousItem(at:placeholder) {
                    try? FileManager.default.startDownloadingUbiquitousItem(at:url)
                    throw DirectoryIssue(kind:.pendingDownload,item:key,underlying:failure.underlying)
                }
            }
            throw failure
        }
    }
    func optionalKind(_ url: URL, _ key: String) throws -> Kind? {
        do { return try kind(url,key) }
        catch let issue as DirectoryIssue where issue.kind == .missing { return nil }
    }
    func list(_ directory: URL, _ key: String) throws -> [URL] {
        do {
            let parent = Self.canonical(directory), urls = try children(directory)
            return try urls.compactMap { url in
                let name = url.lastPathComponent
                guard !name.hasPrefix(".") else { return nil }
                guard ProjectFiles.component(name), Self.canonical(url.deletingLastPathComponent()) == parent else {
                    throw DirectoryIssue(kind:.outside,item:key)
                }
                return directory.appendingPathComponent(name)
            }
        } catch { throw DirectoryIssue.reading(error,item:key) }
    }
    func read(_ url: URL, _ key: String) throws -> Data {
        guard try kind(url,key) == .file else { throw DirectoryIssue(kind:.wrongType,item:key) }
        do { return try bytes(url) }
        catch { throw DirectoryIssue.reading(error,item:key) }
    }
    // Check each component before following the next, including for a directly opened entry.
    func required(_ key: String, at root: URL) throws -> Data {
        guard ProjectFiles.safePath(key) else { throw DirectoryIssue(kind:.outside,item:"入口") }
        let parts = key.components(separatedBy:"/")
        var url = root, path: [String] = []
        for component in parts.dropLast() {
            url.appendPathComponent(component); path.append(component)
            let relative = path.joined(separator:"/")
            guard try kind(url,relative) == .directory else { throw DirectoryIssue(kind:.wrongType,item:relative) }
        }
        return try read(url.appendingPathComponent(parts.last!),key)
    }

    func snapshot(_ root: URL, allowMissingEntry: Bool, trace: DirectoryTrace?, io: DirectoryIO?) throws -> SourceSnapshot {
        try io?.check()
        guard try kind(root,"项目目录") == .directory else { throw DirectoryIssue(kind:.wrongType,item:"项目目录") }
        let manifest = "app/manifest.json"
        var files = [manifest:try required(manifest,at:root)]
        let config = root.appendingPathComponent("runtime.json")
        if try optionalKind(config,"runtime.json") != nil { files["runtime.json"] = try read(config,"runtime.json") }
        let info = try ProjectFiles.metadata(files,folderName:root.lastPathComponent)
        let entry = "app/" + info.entry
        do { files[entry] = try required(entry,at:root) }
        catch let issue as DirectoryIssue where issue.kind == .missing {
            guard allowMissingEntry else { throw MissingProjectEntry(path:entry,mode:info.mode) }
            trace?.event("scan.entryMissing")
        }

        var listedRequired = Set<String>()
        func walk(_ dir: URL, _ prefix: String) throws {
            try io?.check()
            for url in try list(dir,prefix) {
                try io?.check()
                let key = prefix + "/" + url.lastPathComponent
                if key == manifest || key == entry, files[key] != nil { listedRequired.insert(key); continue }
                switch try kind(url,key) {
                case .directory: try walk(url,key)
                case .file: files[key] = try read(url,key)
                }
            }
        }
        for name in ProjectFiles.sourceDirectories {
            let dir = root.appendingPathComponent(name)
            guard let type = try optionalKind(dir,name) else { continue }
            guard type == .directory else { throw DirectoryIssue(kind:.wrongType,item:name) }
            try walk(dir,name)
        }
        if !listedRequired.contains(manifest) { trace?.event("scan.enumerationOmitted","manifest") }
        if files[entry] != nil && !listedRequired.contains(entry) { trace?.event("scan.enumerationOmitted","entry") }
        try io?.check()
        return ProjectFiles.snapshot(info:info, files:files)
    }
}

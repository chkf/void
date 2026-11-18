import Darwin
import Foundation

struct ProjectSourceReader {
    enum Kind { case directory, file }
    var children: (URL) throws -> [URL] = { try FileManager.default.contentsOfDirectory(at:$0,includingPropertiesForKeys:nil) }
    var bytes: ((URL) throws -> Data)?
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
    private func read(_ url: URL, _ key: String, root: URL) throws -> Data {
        guard try kind(url,key) == .file else { throw DirectoryIssue(kind:.wrongType,item:key) }
        do {
            if let bytes { return try bytes(url) }
            // Pin each parent to its descriptor. An editor rename between metadata lookup and
            // the read must not redirect the snapshot through a newly installed symlink.
            var descriptor = Darwin.open(root.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
            defer { Darwin.close(descriptor) }
            let parts = key.components(separatedBy:"/")
            for (offset,part) in parts.enumerated() {
                let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (offset == parts.count - 1 ? O_NONBLOCK : O_DIRECTORY)
                let next = VoidOpenReadChild(descriptor,part,flags)
                guard next >= 0 else {
                    let code = errno
                    if code == ELOOP { throw DirectoryIssue(kind:.link,item:key) }
                    throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))
                }
                Darwin.close(descriptor); descriptor = next
            }
            var item = stat()
            guard fstat(descriptor,&item) == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
            guard (item.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw DirectoryIssue(kind:.wrongType,item:key) }
            return try FileHandle(fileDescriptor:descriptor,closeOnDealloc:false).readToEnd() ?? Data()
        } catch { throw DirectoryIssue.reading(error,item:key) }
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
        return try read(url.appendingPathComponent(parts.last!),key,root:root)
    }

    func configuration(_ root: URL) throws -> (ProjectInfo,[String:Data]) {
        guard try kind(root,"项目目录") == .directory else { throw DirectoryIssue(kind:.wrongType,item:"项目目录") }
        let manifest = "app/manifest.json"
        var files = [manifest:try required(manifest,at:root)]
        let config = root.appendingPathComponent("runtime.json")
        if try optionalKind(config,"runtime.json") != nil { files["runtime.json"] = try read(config,"runtime.json",root:root) }
        return (try ProjectFiles.metadata(files,folderName:root.lastPathComponent),files)
    }

    func snapshot(_ root: URL, allowMissingEntry: Bool, trace: DirectoryTrace?, io: DirectoryIO?) throws -> SourceSnapshot {
        try io?.check()
        let manifest = "app/manifest.json"
        let (info,config) = try configuration(root)
        var files = config
        let entry = "app/" + info.entry
        do { files[entry] = try required(entry,at:root) }
        catch let issue as DirectoryIssue where issue.kind == .missing {
            guard allowMissingEntry else { throw MissingProjectEntry(path:entry,mode:info.mode) }
            trace?.event("scan.entryMissing")
        }

        let boundary = Self.canonical(root)
        var listedRequired = Set<String>()
        func walk(_ dir: URL, _ prefix: String) throws {
            try io?.check()
            guard Self.canonical(dir).starts(with:boundary) else { throw DirectoryIssue(kind:.outside,item:prefix) }
            for url in try list(dir,prefix) {
                try io?.check()
                let key = prefix + "/" + url.lastPathComponent
                if key == manifest || key == entry, files[key] != nil { listedRequired.insert(key); continue }
                switch try kind(url,key) {
                case .directory: try walk(url,key)
                case .file: files[key] = try read(url,key,root:root)
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

import CryptoKit
import Darwin
import Foundation

struct ProjectSourceReader {
    static let configurationByteLimit = 1024 * 1024
    var sourceByteLimit = 96 * 1024 * 1024
    var itemLimit = 24_000

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
            // Some providers omit resource type flags. Obtain the type without following the final link.
            var item = stat()
            if lstat(url.path,&item) == 0 {
                switch item.st_mode & mode_t(S_IFMT) {
                case mode_t(S_IFDIR): return .directory
                case mode_t(S_IFREG): return .file
                case mode_t(S_IFLNK): throw DirectoryIssue(kind:.link,item:key)
                default: throw DirectoryIssue(kind:.wrongType,item:key)
                }
            }
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
    func list(_ directory: URL, _ key: String, trace: DirectoryTrace? = nil, io: DirectoryIO? = nil) throws -> [URL] {
        do {
            let parent = Self.canonical(directory)
            var urls = try children(directory)
            if urls.isEmpty {
                // File Provider can briefly return an empty first listing while materializing a directory.
                try io?.check()
                trace?.event("scan.retryEmpty")
                urls = try children(directory)
            }
            return try urls.compactMap { url in
                let name = url.lastPathComponent
                guard !name.hasPrefix(".") else { return nil }
                guard ProjectFiles.component(name), Self.canonical(url.deletingLastPathComponent()) == parent else {
                    throw DirectoryIssue(kind:.outside,item:key)
                }
                return directory.appendingPathComponent(name)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw DirectoryIssue.reading(error,item:key) }
    }
    private func consume(_ url: URL, _ key: String, root: URL, limit: Int, io: DirectoryIO?,
                         _ receive: (Data) -> Void) throws {
        let limitError = DirectoryIssue(kind:.sourceLimit,item:key + "（剩余可读取 " + String(limit / 1024) + " KiB）")
        guard try kind(url,key) == .file else { throw DirectoryIssue(kind:.wrongType,item:key) }
        do {
            if let bytes {
                let data = try bytes(url)
                guard data.count <= limit else { throw limitError }
                receive(data)
                return
            }
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
            guard item.st_size <= Int64(limit) else { throw limitError }
            let handle = FileHandle(fileDescriptor:descriptor,closeOnDealloc:false)
            var remaining = limit
            while true {
                try io?.check()
                // The extra byte distinguishes EOF from a file that grew after fstat.
                let chunk = try autoreleasepool { try handle.read(upToCount:min(256 * 1024,remaining + 1)) }
                guard let chunk, !chunk.isEmpty else { return }
                guard chunk.count <= remaining else { throw limitError }
                remaining -= chunk.count
                receive(chunk)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw DirectoryIssue.reading(error,item:key) }
    }
    // Check each component before following the next, including for a directly opened entry.
    private func sourceURL(_ key: String, at root: URL) throws -> URL {
        guard ProjectFiles.safePath(key) else { throw DirectoryIssue(kind:.outside,item:"入口") }
        let parts = key.components(separatedBy:"/")
        var url = root, path: [String] = []
        for component in parts.dropLast() {
            url.appendPathComponent(component); path.append(component)
            let relative = path.joined(separator:"/")
            guard try kind(url,relative) == .directory else { throw DirectoryIssue(kind:.wrongType,item:relative) }
        }
        return url.appendingPathComponent(parts.last ?? "")
    }

    func required(_ key: String, at root: URL, limit: Int = Self.configurationByteLimit, io: DirectoryIO? = nil) throws -> Data {
        var data = Data()
        try consume(sourceURL(key,at:root),key,root:root,limit:limit,io:io) { data.append($0) }
        return data
    }

    func configuration(_ root: URL, io: DirectoryIO? = nil) throws -> (ProjectInfo,[String:Data]) {
        guard try kind(root,"项目目录") == .directory else { throw DirectoryIssue(kind:.wrongType,item:"项目目录") }
        let manifest = "app/manifest.json"
        var files = [manifest:try required(manifest,at:root,io:io)]
        let config = root.appendingPathComponent("runtime.json")
        if try optionalKind(config,"runtime.json") != nil { files["runtime.json"] = try required("runtime.json",at:root,io:io) }
        return (try ProjectFiles.metadata(files,folderName:root.lastPathComponent),files)
    }

    func snapshot(_ root: URL, allowMissingEntry: Bool, trace: DirectoryTrace?, io: DirectoryIO?,
                  retainingSources: Bool = true) throws -> SourceSnapshot {
        try io?.check()
        let manifest = "app/manifest.json"
        let (info,config) = try configuration(root,io:io)
        var files = config
        var digests = files.mapValues { SHA256.hash(data:$0) }
        var used = config.values.reduce(0) { $0 + $1.count }
        guard used <= sourceByteLimit else { throw DirectoryIssue(kind:.sourceLimit,item:"项目清单") }
        let entry = "app/" + info.entry
        func collect(_ key: String, _ url: URL) throws {
            if digests[key] != nil { return }
            var hash = SHA256(), content = Data()
            try consume(url,key,root:root,limit:sourceByteLimit-used,io:io) { chunk in
                hash.update(data:chunk)
                used += chunk.count
                if retainingSources { content.append(chunk) }
            }
            digests[key] = hash.finalize()
            if retainingSources { files[key] = content }
        }
        do { try collect(entry,sourceURL(entry,at:root)) }
        catch let issue as DirectoryIssue where issue.kind == .missing {
            guard allowMissingEntry else { throw MissingProjectEntry(path:entry,mode:info.mode) }
            trace?.event("scan.entryMissing")
        }

        let boundary = Self.canonical(root)
        var directories: [(URL,String)] = []
        for name in ProjectFiles.sourceDirectories {
            let dir = root.appendingPathComponent(name)
            guard let type = try optionalKind(dir,name) else { continue }
            guard type == .directory else { throw DirectoryIssue(kind:.wrongType,item:name) }
            directories.append((dir,name))
        }
        var listedRequired = Set<String>(), visited = 0
        while let (dir,prefix) = directories.popLast() {
            try io?.check()
            guard Self.canonical(dir).starts(with:boundary) else { throw DirectoryIssue(kind:.outside,item:prefix) }
            try autoreleasepool {
                for url in try list(dir,prefix,trace:trace,io:io) {
                    try io?.check()
                    visited += 1
                    guard visited <= itemLimit else { throw DirectoryIssue(kind:.sourceLimit,item:"源码目录超过 " + String(itemLimit) + " 项") }
                    let key = prefix + "/" + url.lastPathComponent
                    if key == manifest || key == entry, digests[key] != nil { listedRequired.insert(key); continue }
                    try autoreleasepool {
                        switch try kind(url,key) {
                        case .directory: directories.append((url,key))
                        case .file: try collect(key,url)
                        }
                    }
                }
            }
        }
        if !listedRequired.contains(manifest) { trace?.event("scan.enumerationOmitted","manifest") }
        if digests[entry] != nil && !listedRequired.contains(entry) { trace?.event("scan.enumerationOmitted","entry") }
        try io?.check()
        trace?.event(retainingSources ? "scan.sources" : "scan.fingerprint","files=\(digests.count) bytes=\(used)")
        return SourceSnapshot(info:info,files:files,revision:ProjectFiles.revision(digests))
    }
}

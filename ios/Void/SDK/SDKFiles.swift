import Foundation

final class SDKFiles: @unchecked Sendable {
    let record: ProjectRecord
    private let storage: URL
    private let caches: URL
    let temporary: URL
    static let maxChunk = 4 * 1024 * 1024
    private static let ioLock = NSLock()
    private let fm = FileManager.default

    init(record: ProjectRecord, storage: URL) {
        self.record = record
        self.storage = storage.appendingPathComponent("Projects/" + record.id.uuidString)
        self.caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("void/" + record.id.uuidString)
        self.temporary = FileManager.default.temporaryDirectory.appendingPathComponent("void-session-" + UUID().uuidString)
    }
    deinit { try? fm.removeItem(at: temporary) }

    func temp(_ name: String) throws -> URL {
        let dir = temporary.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(ProjectFiles.component(name) ? name : "file")
    }

    func access<T>(_ path: String, write: Bool = false, io: DirectoryIO? = nil, _ body: (URL) throws -> T) throws -> T {
        try withPaths([path], writing: write ? [0] : [], io:io) { try body($0[0]) }
    }

    private func withPaths<T>(_ paths: [String], writing: Set<Int>, io: DirectoryIO? = nil, _ body: ([URL]) throws -> T) throws -> T {
        let parts = try paths.enumerated().map { index, path -> [String] in
            guard ProjectFiles.safePath(path) else { throw SDKFailure.denied("需要项目内的相对路径") }
            let components = path.components(separatedBy: "/")
            guard ["data","project","private","cache"].contains(components[0]) else { throw SDKFailure.denied("请选择 data/、project/、private/ 或 cache/ 内的路径") }
            guard !writing.contains(index) || components.count > 1 else { throw SDKFailure.denied("请选择目录内的文件") }
            return components
        }
        func resolve(_ base: URL, _ parts: [String]) throws -> URL {
            var url = base
            for component in parts {
                url.appendPathComponent(component)
                do {
                    let attrs = try fm.attributesOfItem(atPath: url.path)
                    guard attrs[.type] as? FileAttributeType != .typeSymbolicLink else { throw SDKFailure.denied("文件路径包含符号链接") }
                } catch let error as NSError where error.domain == NSCocoaErrorDomain
                    && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                    continue
                }
            }
            return url
        }
        func use(_ shared: URL?) throws -> T {
            Self.ioLock.lock()
            defer { Self.ioLock.unlock() }
            try io?.check()
            try Task.checkCancellation()
            let urls = try parts.map { components -> URL in
                let scope = components[0]
                if scope == "data" || scope == "project" {
                    guard let shared else { throw SDKFailure.denied("项目目录不可用") }
                    return try resolve(shared, scope == "data" ? components : Array(components.dropFirst()))
                }
                let root = scope == "private" ? storage.appendingPathComponent("Files") : caches
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                return try resolve(root, Array(components.dropFirst()))
            }
            return try body(urls)
        }
        if parts.contains(where: { $0[0] == "data" || $0[0] == "project" }) {
            return try record.grant.coordinated(write: !writing.isEmpty,io:io) { root in
                guard try ProjectLibrary.directoryKey(root) == record.directoryKey else { throw SDKFailure.denied("项目文件夹已变更，请重新授权") }
                return try use(root)
            }
        }
        return try use(nil)
    }

    func input(_ path: String) throws -> URL {
        try access(path) { source in
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw SDKFailure.invalid("path") }
            let copy = try temp(source.lastPathComponent)
            try fm.copyItem(at: source, to: copy)
            return copy
        }
    }

    func store(_ source: URL, at path: String, replace: Bool = true) throws {
        try access(path, write: true) { target in
            let parent = target.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            let staging = parent.appendingPathComponent(".void-" + UUID().uuidString)
            try fm.copyItem(at: source, to: staging)
            defer { try? fm.removeItem(at: staging) }
            if replace && fm.fileExists(atPath: target.path) {
                guard try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw SDKFailure.invalid("path") }
                _ = try fm.replaceItemAt(target, withItemAt: staging)
            } else { try fm.moveItem(at: staging, to: target) }
        }
    }

    private func info(_ url: URL) throws -> [String: Any] {
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let type = attrs[.type] as? FileAttributeType
        return ["name": url.lastPathComponent, "type": type == .typeDirectory ? "directory" : (type == .typeSymbolicLink ? "link" : "file"),
                "size": attrs[.size] as? NSNumber ?? 0, "modified": (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0]
    }
    func signature(_ path: String) async throws -> Data {
        try await DirectoryIO.run { io in
            try self.access(path,io:io) { url in
                guard self.fm.fileExists(atPath:url.path) else { return Data() }
                let entry = try self.info(url)
                let children = (entry["type"] as? String == "directory") ? try self.fm.contentsOfDirectory(at:url,includingPropertiesForKeys:nil)
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }.map { child in
                        try io.check()
                        return try self.info(child)
                    } : []
                return try JSONSerialization.data(withJSONObject:[entry] + children,options:[.sortedKeys])
            }
        }
    }

    func call(_ method: String, _ a: SDKArgs) throws -> Any {
        let path = try a.string("path")
        switch method {
        case "exists": return try access(path) { fm.fileExists(atPath: $0.path) }
        case "stat": return try access(path, info)
        case "readdir":
            return try access(path) { try fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }.map(info) }
        case "mkdir":
            try access(path, write: true) { try fm.createDirectory(at: $0, withIntermediateDirectories: true) }
        case "deleteFile":
            try access(path, write: true) { url in
                if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                   !(try fm.contentsOfDirectory(atPath: url.path)).isEmpty { throw SDKFailure("NOT_EMPTY", "目录中仍有文件") }
                try fm.removeItem(at: url)
            }
        case "copyFile", "moveFile":
            let target = try a.string("to")
            try withPaths([path,target], writing:method == "moveFile" ? [0,1] : [1]) { urls in
                let from = urls[0], to = urls[1]
                guard try from.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true else { throw SDKFailure.invalid("path") }
                if from.standardizedFileURL == to.standardizedFileURL { return }
                try fm.createDirectory(at:to.deletingLastPathComponent(),withIntermediateDirectories:true)
                if method == "moveFile" { try fm.moveItem(at:from,to:to) }
                else { try fm.copyItem(at:from,to:to) }
            }
        case "readFile", "readChunk":
            let encoding = try a.choice("encoding", ["utf8", "base64"], method == "readChunk" ? "base64" : "utf8")
            return try access(path) { url in
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let offset = try a.int("offset", 0)
                let limit = method == "readChunk" ? try a.int("length", Self.maxChunk, range: 1...Self.maxChunk) : Self.maxChunk + 1
                try handle.seek(toOffset: UInt64(offset))
                let data = try handle.read(upToCount: limit) ?? Data()
                guard data.count <= Self.maxChunk else { throw SDKFailure("TOO_LARGE", "请用 readChunk 分块读取") }
                if encoding == "base64" { return data.base64EncodedString() }
                guard let text = String(data: data, encoding: .utf8) else { throw SDKFailure("INVALID_ENCODING", "请以 base64 读取二进制文件") }
                return text
            }
        case "writeFile", "appendFile", "writeChunk":
            let encoding = try a.choice("encoding", ["utf8", "base64"], method == "writeChunk" ? "base64" : "utf8")
            let data = encoding == "base64" ? try a.data("data") : Data(try a.string("data").utf8)
            guard data.count <= Self.maxChunk else { throw SDKFailure("TOO_LARGE", "请用 writeChunk 分块写入") }
            try access(path, write: true) { url in
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if method == "writeFile" { try data.write(to: url, options: .atomic); return }
                if !fm.fileExists(atPath: url.path) { try Data().write(to: url, options: .withoutOverwriting) }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                let end = try handle.seekToEnd()
                if method == "writeChunk" {
                    let offset = UInt64(try a.int("offset"))
                    guard offset <= end else { throw SDKFailure.invalid("offset") }
                    try handle.seek(toOffset: offset)
                }
                try handle.write(contentsOf: data)
            }
        default: throw SDKFailure("UNKNOWN_METHOD", method)
        }
        return NSNull()
    }
}

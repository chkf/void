import Foundation

final class SDKFiles: @unchecked Sendable {
    let record: ProjectRecord
    private let storage: URL
    private let caches: URL
    let temporary: URL
    static let maxChunk = 4 * 1024 * 1024
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

    func access<T>(_ path: String, write: Bool = false, _ body: (URL) throws -> T) throws -> T {
        guard ProjectFiles.safePath(path) else { throw SDKFailure.denied("需要项目内的相对路径") }
        let components = path.components(separatedBy: "/")
        let scope = components[0]
        guard !write || components.count > 1 else { throw SDKFailure.denied("请选择目录内的文件") }
        func resolve(_ base: URL, _ parts: [String]) throws -> T {
            var url = base
            for component in parts {
                url.appendPathComponent(component)
                do {
                    let attrs = try fm.attributesOfItem(atPath: url.path)
                    guard attrs[.type] as? FileAttributeType != .typeSymbolicLink else { throw SDKFailure.denied("文件路径包含符号链接") }
                } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {}
            }
            return try body(url)
        }
        switch scope {
        case "data", "project":
            return try record.grant.coordinated(write: write) { root in
                guard try ProjectLibrary.directoryKey(root) == record.directoryKey else { throw SDKFailure.denied("项目文件夹已变更，请重新授权") }
                return try resolve(root, scope == "data" ? components : Array(components.dropFirst()))
            }
        case "private", "cache":
            let root = scope == "private" ? storage.appendingPathComponent("Files") : caches
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            return try resolve(root, Array(components.dropFirst()))
        default: throw SDKFailure.denied("请选择 data/、project/、private/ 或 cache/ 内的路径")
        }
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
    func signature(_ path: String) throws -> Data {
        try access(path) { url in
            guard fm.fileExists(atPath: url.path) else { return Data() }
            let entry = try info(url)
            let children = (entry["type"] as? String == "directory") ? try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }.map(info) : []
            return try JSONSerialization.data(withJSONObject: [entry] + children, options: [.sortedKeys])
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
            let same = try access(path) { $0.standardizedFileURL } == access(target) { $0.standardizedFileURL }
            if same { return NSNull() }
            let copy = try input(path)
            try store(copy, at: target, replace: false)
            if method == "moveFile" { try access(path, write: true) { try fm.removeItem(at: $0) } }
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

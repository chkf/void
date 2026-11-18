import CryptoKit
import Foundation

struct RuntimeIssue: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum UIMode: String, Codable { case swiftui, native, web }

enum ProjectTemplate: String, Codable {
    case swiftUI = "StarterProject"
    case tsx = "TSXProject"

    var entry: String { self == .swiftUI ? "app/" + CompiledProject.entry : "app/src/main.tsx" }
    var title: String { self == .swiftUI ? "SwiftUI" : "React / TSX" }
}

struct ProjectInfo {
    let declaredID: String?
    let name: String
    let version: String
    let mode: UIMode
    let entry: String
    let permissions: [String]
}

struct SourceSnapshot {
    let info: ProjectInfo
    let files: [String: Data]
    let revision: String
}

enum ProjectFiles {
    static let manager = FileManager.default
    static let sourceDirectories = ["app", "assets", "modules"]

    static func component(_ text: String) -> Bool {
        !text.isEmpty && text != "." && text != ".." && !text.contains("/")
            && !text.contains("\\") && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func safePath(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component(String($0)) }
    }

    static func dictionary(_ bytes: Data?, file: String) throws -> [String: Any] {
        guard let bytes else { throw RuntimeIssue("缺少 " + file) }
        do {
            guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw RuntimeIssue("需要 JSON 对象")
            }
            return object
        } catch { throw RuntimeIssue(file + " · " + error.localizedDescription) }
    }

    static func info(_ files: [String: Data], folderName: String) throws -> ProjectInfo {
        var id: String?
        if let data = files["runtime.json"] {
            let config = try dictionary(data, file: "runtime.json")
            if let version = config["formatVersion"], version as? Int != 1 {
                throw RuntimeIssue("runtime.json · 不支持此 formatVersion")
            }
            if let raw = config["id"] {
                guard let value = raw as? String, !value.isEmpty else { throw RuntimeIssue("runtime.json · id 需要非空文本") }
                id = value
            }
        }
        let manifest = try dictionary(files["app/manifest.json"], file: "app/manifest.json")
        let defaultEntry: String
        switch manifest["uiMode"] as? String {
        case "swiftui": defaultEntry = CompiledProject.entry
        case "native": defaultEntry = "src/main.tsx"
        default: defaultEntry = "index.html"
        }
        let entry = (manifest["entry"] as? String) ?? defaultEntry
        guard safePath(entry), files["app/" + entry] != nil else {
            throw RuntimeIssue("app/manifest.json · 入口无效或缺失 " + entry)
        }
        let mode = try modeForManifest(manifest, entry: entry)
        let permissions = manifest["permissions"] as? [String] ?? []
        if manifest["permissions"] != nil && !(manifest["permissions"] is [String]) {
            throw RuntimeIssue("app/manifest.json · permissions 需要字符串数组")
        }
        return ProjectInfo(declaredID: id ?? manifest["id"] as? String,
                           name: manifest["name"] as? String ?? folderName,
                           version: manifest["version"] as? String ?? "1.0.0", mode: mode,
                           entry: entry, permissions: permissions)
    }

    private static func modeForManifest(_ manifest: [String: Any], entry: String) throws -> UIMode {
        if let value = manifest["uiMode"] {
            guard let text = value as? String, let mode = UIMode(rawValue: text) else {
                throw RuntimeIssue("app/manifest.json · 未知的 uiMode")
            }
            if mode == .swiftui || mode == .native { return mode }
        }
        guard ["html", "htm"].contains((entry as NSString).pathExtension.lowercased()) else {
            throw RuntimeIssue("app/manifest.json · Web 项目需要 HTML 入口")
        }
        return .web
    }

    static func checkLink(_ url: URL) throws {
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw RuntimeIssue("项目源码不能通过符号链接读取 · " + url.lastPathComponent)
        }
    }

    static func snapshot(at root: URL) throws -> SourceSnapshot {
        try checkLink(root)
        var files: [String: Data] = [:]
        let config = root.appendingPathComponent("runtime.json")
        if manager.fileExists(atPath: config.path) {
            try checkLink(config)
            files["runtime.json"] = try Data(contentsOf: config)
        }
        for name in sourceDirectories {
            let dir = root.appendingPathComponent(name)
            guard manager.fileExists(atPath: dir.path) else { continue }
            try checkLink(dir)
            var failure: Error?
            guard let walker = manager.enumerator(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
                                                  options: [.skipsHiddenFiles], errorHandler: { _, error in
                failure = error
                return false
            }) else { throw RuntimeIssue("无法读取目录 " + name) }
            for case let file as URL in walker {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw RuntimeIssue("源码包含符号链接 · " + file.lastPathComponent) }
                if values.isRegularFile == true {
                    let path = file.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
                    guard safePath(path) else { throw RuntimeIssue("无效的源文件路径 " + path) }
                    files[path] = try Data(contentsOf: file)
                }
            }
            if let failure { throw failure }
        }
        let metadata = try info(files, folderName: root.lastPathComponent)
        var hash = SHA256()
        for name in files.keys.sorted() {
            hash.update(data: Data(name.utf8))
            hash.update(data: Data([0]))
            hash.update(data: Data(SHA256.hash(data: files[name]!)))
        }
        let revision = hash.finalize().map { String(format: "%02x", $0) }.joined()
        return SourceSnapshot(info: metadata, files: files, revision: revision)
    }

    static func rename(_ name: String, at root: URL) throws {
        let manifest = root.appendingPathComponent("app/manifest.json")
        try checkLink(root.appendingPathComponent("app"))
        try checkLink(manifest)
        var value = try dictionary(Data(contentsOf: manifest), file: "app/manifest.json")
        value["name"] = name
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: manifest, options: .atomic)
    }

    static func create(_ name: String, in parent: URL, template: ProjectTemplate = .swiftUI) throws -> URL {
        guard component(name), !name.hasPrefix(".") else { throw RuntimeIssue("请输入有效的项目文件夹名称") }
        let target = parent.appendingPathComponent(name, isDirectory: true)
        guard !manager.fileExists(atPath: target.path) else { throw RuntimeIssue("此位置已有同名文件或目录") }
        guard let source = Bundle.main.url(forResource: template.rawValue, withExtension: nil) else {
            throw RuntimeIssue("宿主缺少项目模板")
        }
        let staging = parent.appendingPathComponent(".void-new-" + UUID().uuidString)
        try manager.copyItem(at: source, to: staging)
        defer { if manager.fileExists(atPath: staging.path) { try? manager.removeItem(at: staging) } }
        let config: [String: Any] = ["formatVersion": 1, "id": UUID().uuidString]
        try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            .write(to: staging.appendingPathComponent("runtime.json"), options: .atomic)
        try rename(name, at: staging)
        for path in ["assets", "modules", "data", "logs"] {
            try manager.createDirectory(at: staging.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try manager.moveItem(at: staging, to: target)
        return target
    }
}

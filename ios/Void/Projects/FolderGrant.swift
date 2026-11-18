import Foundation

struct FolderAccessIssue: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct FolderGrant: Codable {
    var bookmark: Data?
    var child: String
    var localFolder: String? = nil

    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func selected(_ url: URL, child: String = "") throws -> Self {
        let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let base = documents.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        if parts.starts(with: base) {
            let local = parts.dropFirst(base.count).joined(separator: "/")
            return Self(bookmark: nil, child: child, localFolder: local)
        }
        return try scoped(url) {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            return Self(bookmark: bookmark, child: child)
        }
    }

    private static func scoped<T>(_ url: URL, body: () throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else { throw FolderAccessIssue("目录授权已失效，请重新选择文件夹") }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body()
    }

    func withRoot<T>(_ body: (URL) throws -> T) throws -> T {
        guard child.isEmpty || ProjectFiles.component(child) else { throw RuntimeIssue("登记的目录名称无效") }
        guard let bookmark else {
            let parts = [localFolder ?? "", child].filter { !$0.isEmpty }
            guard parts.allSatisfy(ProjectFiles.safePath) else { throw FolderAccessIssue("本地目录路径无效") }
            let documents = Self.documents.standardizedFileURL.resolvingSymlinksInPath()
            let root = parts.reduce(documents) { $0.appendingPathComponent($1) }
            guard root.resolvingSymlinksInPath().pathComponents.starts(with: documents.pathComponents) else {
                throw FolderAccessIssue("目录已移出本应用的文稿范围")
            }
            return try body(root)
        }
        var stale = false
        let parent: URL
        do { parent = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw FolderAccessIssue("无法恢复目录授权，请重新选择文件夹") }
        guard !stale else { throw FolderAccessIssue("目录书签已过期，请重新选择文件夹") }
        return try Self.scoped(parent) { try body(child.isEmpty ? parent : parent.appendingPathComponent(child)) }
    }

    func coordinated<T>(write: Bool = false, _ body: (URL) throws -> T) throws -> T {
        try withRoot { root in
            let coordinator = NSFileCoordinator()
            var failure: NSError?
            var result: Result<T, Error>?
            if write {
                coordinator.coordinate(writingItemAt: root, options: .forMerging, error: &failure) { url in
                    result = Result { try body(url) }
                }
            } else {
                coordinator.coordinate(readingItemAt: root, options: [], error: &failure) { url in
                    result = Result { try body(url) }
                }
            }
            if let failure { throw failure }
            guard let result else { throw RuntimeIssue("文件服务商尚未提供目录内容") }
            return try result.get()
        }
    }
}

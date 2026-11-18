import Foundation

struct FolderGrant: Codable {
    var bookmark: Data?
    var child: String

    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func selected(_ url: URL, child: String = "") throws -> Self {
        try scoped(url) {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            return Self(bookmark: bookmark, child: child)
        }
    }

    private static func scoped<T>(_ url: URL, body: () throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else { throw RuntimeIssue("目录授权已失效，请重新选择文件夹") }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body()
    }

    func withRoot<T>(_ body: (URL) throws -> T) throws -> T {
        guard child.isEmpty || ProjectFiles.component(child) else { throw RuntimeIssue("登记的目录名称无效") }
        guard let bookmark else {
            return try body(child.isEmpty ? Self.documents : Self.documents.appendingPathComponent(child))
        }
        var stale = false
        let parent = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw RuntimeIssue("目录书签已过期，请重新选择文件夹") }
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

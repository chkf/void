import Foundation

struct FolderAccessIssue: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class SelectionLease {
    let url: URL
    let scoped: Bool
    init(_ url: URL) { self.url = url; scoped = url.startAccessingSecurityScopedResource() }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

struct FolderGrant: Codable, Equatable {
    var bookmark: Data?
    var child: String
    var localFolder: String? = nil
    static var documents: URL { FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0] }
    private var localComponents: [String] {
        [localFolder ?? "",child].filter { !$0.isEmpty }.flatMap { $0.components(separatedBy:"/") }
    }
    static func selected(_ url: URL, child: String = "") throws -> Self {
        guard url.isFileURL else { throw DirectoryIssue(kind:.wrongType,item:"所选目录") }
        let parts = ProjectSourceReader.canonical(url), base = ProjectSourceReader.canonical(documents)
        if parts.starts(with:base) {
            let local = parts.dropFirst(base.count).joined(separator:"/")
            return Self(bookmark:nil,child:child,localFolder:local)
        }
        return try scoped(url) {
            Self(bookmark:try url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil),child:child)
        }
    }
    private static func scoped<T>(_ url: URL, body: () throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else { throw DirectoryIssue(kind:.unreadable,item:"外部目录授权") }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body()
    }
    private func resolved(_ stale: inout Bool) throws -> URL {
        guard let bookmark else { return Self.documents }
        do { return try URL(resolvingBookmarkData:bookmark,options:[.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale) }
        catch { throw DirectoryIssue.reading(error,item:"原目录书签") }
    }
    func watcherRoot() throws -> (URL,SelectionLease?) {
        var stale = false
        let lease = try bookmark.map { _ in SelectionLease(try resolved(&stale)) }
        if let lease, !lease.scoped { throw DirectoryIssue(kind:.unreadable,item:"外部目录授权") }
        return try withRoot { ($0,lease) }
    }
    func refreshed() throws -> Self {
        guard bookmark != nil else { return self }
        var stale = false
        let parent = try resolved(&stale)
        guard stale else { return self }
        return try Self.scoped(parent) {
            Self(bookmark:try parent.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil),child:child)
        }
    }
    func sameLocation(as other: Self) -> Bool {
        if bookmark == nil && other.bookmark == nil { return localComponents == other.localComponents }
        if self == other { return true }
        func location(_ grant: Self) throws -> [String] {
            var stale = false
            let base = try grant.resolved(&stale)
            let components = grant.bookmark == nil ? grant.localComponents : [grant.child].filter { !$0.isEmpty }
            return ProjectSourceReader.canonical(components.reduce(base) { $0.appendingPathComponent($1) })
        }
        guard let a = try? location(self), let b = try? location(other) else { return false }
        return a == b
    }
    func withRoot<T>(_ body: (URL) throws -> T) throws -> T {
        guard child.isEmpty || ProjectFiles.component(child) else { throw DirectoryIssue(kind:.outside,item:"登记目录") }
        var stale = false
        let parent = try resolved(&stale)
        let reader = ProjectSourceReader()
        func descend(_ url: URL, _ parts: [String]) throws -> T {
            var root = url
            for part in parts {
                guard ProjectFiles.component(part) else { throw DirectoryIssue(kind:.outside,item:"登记目录") }
                root.appendPathComponent(part)
                guard try reader.kind(root,"登记目录") == .directory else { throw DirectoryIssue(kind:.wrongType,item:"登记目录") }
            }
            guard ProjectSourceReader.canonical(root).starts(with:ProjectSourceReader.canonical(url)) else { throw DirectoryIssue(kind:.outside,item:"登记目录") }
            return try body(root)
        }
        if bookmark == nil { return try descend(parent,localComponents) }
        return try Self.scoped(parent) { try descend(parent,child.isEmpty ? [] : [child]) }
    }

    func coordinated<T>(write: Bool = false, io: DirectoryIO? = nil, trace: DirectoryTrace? = nil, _ body: (URL) throws -> T) throws -> T {
        trace?.event("grant.begin",bookmark == nil ? "Documents" : "bookmark")
        do {
            let value = try withRoot { root in
                try io?.check()
                let coordinator = NSFileCoordinator()
                func coordinate() throws -> T {
                    var error: NSError?
                    var result: Result<T,Error>?
                    func accessor(_ url: URL) {
                        result = Result {
                            try io?.check()
                            guard ProjectSourceReader.canonical(url) == ProjectSourceReader.canonical(root) else { throw DirectoryIssue(kind:.outside,item:"协调根目录") }
                            trace?.event("grant.accessor")
                            return try body(url)
                        }
                    }
                    if write { coordinator.coordinate(writingItemAt:root,options:.forMerging,error:&error,byAccessor:accessor) }
                    else { coordinator.coordinate(readingItemAt:root,options:[],error:&error,byAccessor:accessor) }
                    try io?.check()
                    if let error { throw DirectoryIssue.reading(error,item:"目录协调") }
                    guard let result else { throw DirectoryIssue(kind:.provider,item:"目录协调") }
                    return try result.get()
                }
                if let io { return try io.withCoordinator(coordinator,coordinate) }
                return try coordinate()
            }
            trace?.event("grant.end","OK")
            return value
        } catch { trace?.event("grant.end","失败",error:error); throw error }
    }
}

import Foundation

final class SourceWatcher: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let changed: () -> Void
    private var observing = true
    private var lease: SelectionLease?

    static func start(grant: FolderGrant, changed: @escaping () -> Void) async throws -> SourceWatcher {
        let (root,scope) = try await DirectoryIO.run { _ in try grant.watcherRoot() }
        try Task.checkCancellation()
        let watcher = SourceWatcher(root:root,changed:changed)
        watcher.lease = scope
        return watcher
    }

    init(root: URL, changed: @escaping () -> Void) {
        presentedItemURL = root
        self.changed = changed
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() {
        guard observing else { return }
        observing = false
        NSFileCoordinator.removeFilePresenter(self)
        lease = nil
    }
    func presentedItemDidChange() { changed() }
    func presentedSubitemDidAppear(at url: URL) { notify(url) }
    func presentedSubitemDidChange(at url: URL) { notify(url) }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { notify(oldURL); notify(newURL) }
    private func notify(_ url: URL) {
        guard let root = presentedItemURL else { return }
        let base = ProjectSourceReader.canonical(root), path = ProjectSourceReader.canonical(url)
        guard path.starts(with:base), let first = path.dropFirst(base.count).first else { return }
        if first == "runtime.json" || ProjectFiles.sourceDirectories.contains(first) { changed() }
    }
}

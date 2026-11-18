import Foundation

final class SourceWatcher: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let changed: () -> Void

    init(root: URL, changed: @escaping () -> Void) {
        presentedItemURL = root
        self.changed = changed
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }
    func presentedItemDidChange() { changed() }
    func presentedSubitemDidAppear(at url: URL) { notify(url) }
    func presentedSubitemDidChange(at url: URL) { notify(url) }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { notify(oldURL); notify(newURL) }
    private func notify(_ url: URL) {
        guard let root = presentedItemURL,
              let first = url.pathComponents.dropFirst(root.pathComponents.count).first else { return }
        if first == "runtime.json" || ProjectFiles.sourceDirectories.contains(first) { changed() }
    }
}

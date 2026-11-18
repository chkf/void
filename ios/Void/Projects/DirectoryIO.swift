import Foundation

// The provider can keep executing an accessor after cancel(). Keep the scope on the worker,
// detach the waiter immediately, and prevent an abandoned scan from publishing its result.
final class DirectoryIO: @unchecked Sendable {
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "void.project-directory"
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let lock = NSLock()
    private var stopped: Error?
    private var finished = false
    private var cancellation: ((Error) -> Void)?
    private var coordinator: NSFileCoordinator?

    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if let stopped { throw stopped }
    }
    func withCoordinator<T>(_ coordinator: NSFileCoordinator, _ body: () throws -> T) throws -> T {
        lock.lock()
        if let stopped { lock.unlock(); throw stopped }
        self.coordinator = coordinator
        lock.unlock()
        defer { lock.lock(); self.coordinator = nil; lock.unlock() }
        return try body()
    }
    private func cancel(_ error: Error) {
        lock.lock()
        guard !finished, stopped == nil else { lock.unlock(); return }
        stopped = error
        let finish = cancellation, active = coordinator
        cancellation = nil
        lock.unlock()
        active?.cancel()
        finish?(error)
    }
    static func run<T>(timeout: TimeInterval = 20, _ body: @escaping (DirectoryIO) throws -> T) async throws -> T {
        let job = DirectoryIO()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T,Error>) in
                job.start(continuation, timeout:timeout, body)
            }
        } onCancel: { job.cancel(CancellationError()) }
    }
    private func start<T>(_ continuation: CheckedContinuation<T,Error>, timeout: TimeInterval, _ body: @escaping (DirectoryIO) throws -> T) {
        lock.lock()
        if let stopped { lock.unlock(); continuation.resume(throwing:stopped); return }
        cancellation = { continuation.resume(throwing:$0) }
        lock.unlock()
        let timer = DispatchWorkItem { [weak self] in self?.cancel(DirectoryIssue(kind:.timeout,item:"目录协调或读取")) }
        DispatchQueue.global().asyncAfter(deadline:.now()+timeout,execute:timer)
        Self.queue.addOperation {
            let result = Result { try self.check(); return try body(self) }
            timer.cancel()
            self.lock.lock()
            let deliver = self.stopped == nil
            self.finished = true
            self.cancellation = nil
            self.lock.unlock()
            if deliver { continuation.resume(with:result) }
        }
    }
}

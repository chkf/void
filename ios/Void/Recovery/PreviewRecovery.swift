import Foundation

enum PreviewStage: String, Codable {
    case scan, cache, compiler, compile, verify, firstFrame
    var title: String {
        switch self {
        case .scan: return "正在读取项目清单和源码"
        case .cache: return "正在检查可运行版本"
        case .compiler: return "正在启动离线编译器"
        case .compile: return "正在编译项目"
        case .verify: return "正在核对编译后的源码"
        case .firstFrame: return "正在等待项目首屏"
        }
    }
}

struct PreviewAttempt: Codable {
    let request: UUID
    let project: UUID
    let stage: PreviewStage
}

// This file belongs to the host. Leave the catalog, source and confirmed Builds intact
// if the OS ends the app while a candidate is being compiled or rendered.
actor PreviewRecovery {
    private let file: URL
    init(storage: URL) { file = storage.appendingPathComponent("preview-attempt.json") }

    func pending() throws -> PreviewAttempt? {
        do { return try JSONDecoder().decode(PreviewAttempt.self,from:Data(contentsOf:file)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
    }

    func mark(_ attempt: PreviewAttempt, starting: Bool) throws {
        try Task.checkCancellation()
        if !starting, try pending()?.request != attempt.request { throw CancellationError() }
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(attempt).write(to:file,options:.atomic)
    }

    func finish(_ request: UUID) throws {
        if try pending()?.request == request { try FileManager.default.removeItem(at:file) }
    }
}

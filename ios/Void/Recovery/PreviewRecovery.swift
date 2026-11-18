import Foundation

enum PreviewStage: String, Codable {
    case legacyPreparation, scan, cache, compiler, compile, verify, firstFrame
    var title: String {
        switch self {
        case .legacyPreparation: return "旧版准备预览"
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

    static func interruptedLegacyRequest(_ entries: [DirectoryEvent]) -> UUID? {
        guard let begin = entries.lastIndex(where:{ $0.stage == "preview.begin" }) else { return nil }
        let id = entries[begin].request
        let terminal = ["preview.result","scan.result","preview.cancel","preview.superseded","preview.interrupted"]
        // dev.5 has its own atomic marker, beginning at preview.scan.
        let known = entries[begin...].contains { $0.request == id && (terminal.contains($0.stage) || $0.stage == "preview.scan") }
        return known ? nil : id
    }

    static func interruptedLocalScan(_ entries: [DirectoryEvent]) -> (UUID,String)? {
        let starts = ["local.request","picker.request","preview.begin","workspace.begin"]
        guard let start = entries.last(where:{ starts.contains($0.stage) }), start.stage == "local.request" else { return nil }
        let request = entries.filter { $0.request == start.request }
        guard !request.contains(where:{ $0.stage == "local.result" || $0.stage == "local.interrupted" }) else { return nil }
        let stage = request.last?.stage ?? start.stage
        return (start.request,stage)
    }

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

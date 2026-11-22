import Foundation

enum PreviewStage: String, Codable {
    case legacyPreparation, scan, cache, compiler, compile, verify, firstFrame, verifyPage, displayPage, saveBuild
    var title: String {
        switch self {
        case .legacyPreparation: return "旧版准备预览"
        case .scan: return "正在读取项目清单和源码"
        case .cache: return "正在检查可运行版本"
        case .compiler: return "正在启动离线编译器"
        case .compile: return "正在编译项目"
        case .verify: return "正在核对编译后的源码"
        case .firstFrame: return "正在等待项目首屏"
        case .verifyPage: return "首屏内容已就绪，正在复核源码"
        case .displayPage: return "正在将首屏显示到窗口"
        case .saveBuild: return "首屏已显示，正在保存可运行版本"
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

    static func interruptionTitle(_ attempt: PreviewAttempt, entries: [DirectoryEvent]) -> String {
        let request = entries.filter { $0.request == attempt.request }
        if let consent = request.last(where:{ $0.stage == "sdk.consent.begin" || $0.stage == "sdk.consent.end" }),
           consent.stage == "sdk.consent.begin" {
            return "正在等待项目权限选择（" + consent.detail + "）"
        }
        guard attempt.stage == .firstFrame else { return attempt.stage.title }
        let start = request.lastIndex { $0.stage == "preview.firstFrame" } ?? request.startIndex
        let events = request[start...]
        let stages = Set(events.map(\.stage))
        if stages.contains("page.contentReady") || stages.contains("page.firstFrame") { return "首屏内容已就绪，等待显示" }
        if stages.contains("page.nativeCommitReceived") { return "正在处理项目提交的原生控件" }
        if stages.contains("page.sdkReturned") { return "首次原生调用已返回，等待项目提交首屏" }
        if stages.contains("page.sdkConsentPending") { return "正在等待项目首次原生调用的权限选择" }
        if let method = events.last(where:{ $0.stage == "page.sdkMethod" }) {
            return "正在等待首屏的原生调用 " + method.detail
        }
        if stages.contains("page.documentLoaded") || stages.contains("page.navigationFinished") { return "网页已载入，等待项目提交首屏" }
        if stages.contains("page.navigationCommitted") || stages.contains("page.load") { return "正在载入项目首屏网页" }
        return attempt.stage.title
    }

    static func interruptedLegacyRequest(_ entries: [DirectoryEvent]) -> UUID? {
        guard let begin = entries.lastIndex(where:{ $0.stage == "preview.begin" }) else { return nil }
        let id = entries[begin].request
        let terminal = ["preview.result","scan.result","preview.cancel","preview.superseded","preview.interrupted"]
        // dev.5 has its own atomic marker, beginning at preview.scan.
        let known = entries[begin...].contains { $0.request == id && (terminal.contains($0.stage) || $0.stage == "preview.scan") }
        return known ? nil : id
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

import Foundation
import MetricKit
import OSLog

// System reports may arrive on a later launch. Keep them separate from the request in
// progress at delivery time. Neither call stacks nor project content enter this journal.
final class HostExitDiagnostics: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let trace = DirectoryTrace("iOS")
            for crash in payload.crashDiagnostics ?? [] {
                let signal = crash.signal?.stringValue ?? "?"
                let type = crash.exceptionType?.stringValue ?? "?"
                let reason = (crash.terminationReason ?? "").lowercased()
                let category = ["0x8badf00d","watchdog","jetsam","memory","codesign","dyld"].first(where: reason.contains)
                trace.event("system.crash","版本 " + crash.applicationVersion + " · signal " + signal + " · exception " + type +
                            (category.map { " · " + $0 } ?? ""))
            }
            for hang in payload.hangDiagnostics ?? [] {
                let seconds = hang.hangDuration.converted(to:.seconds).value
                trace.event("system.hang","版本 " + hang.applicationVersion + " · " + String(format:"%.1f 秒",seconds))
            }
        }
    }
    func subscribe() { MXMetricManager.shared.add(self) }
}

struct DirectoryIssue: LocalizedError, CustomNSError {
    enum Kind: Int { case missing = 1, unreadable, pendingDownload, invalidJSON, wrongType, link, outside, provider, timeout, identity, emptySelection, noProjects, pickerUnavailable, sourceLimit }
    let kind: Kind
    let item: String
    var underlying: NSError? = nil
    static let errorDomain = "Void.Directory"
    var errorCode: Int { kind.rawValue }
    var errorUserInfo: [String:Any] {
        var value: [String:Any] = [NSLocalizedDescriptionKey:errorDescription ?? ""]
        if let underlying { value[NSUnderlyingErrorKey] = underlying }
        return value
    }
    var errorDescription: String? {
        let message: String
        switch kind {
        case .missing: message = "文件或目录不存在"
        case .unreadable: message = "无法读取，请检查目录的读取权限"
        case .pendingDownload: message = "内容尚未下载到本机"
        case .invalidJSON: message = "JSON 格式无效，需要有效的 JSON 对象"
        case .wrongType: message = "文件类型不符合项目格式"
        case .link: message = "项目源码路径包含符号链接"
        case .outside: message = "文件服务商返回了项目目录以外的位置"
        case .provider: message = "文件服务商暂时无法提供内容"
        case .timeout: message = "等待文件服务商超时，已取消本次目录操作"
        case .identity: message = "目录或 runtime.json 身份与原登记不符，已保留原记录"
        case .emptySelection: message = "系统文件选择器未返回目录"
        case .noProjects: message = "此目录没有可识别的项目"
        case .pickerUnavailable: message = "系统未能显示文件选择器"
        case .sourceLimit: message = "本次读取达到预览容量限制，已停止读取"
        }
        let native = underlying.map { " (\($0.domain) \($0.code))" } ?? ""
        return [HostLanguage.text(item), HostLanguage.text(message) + native].filter { !$0.isEmpty }.joined(separator:" · ")
    }
    static func reading(_ error: Error, item: String) -> DirectoryIssue {
        if let issue = error as? DirectoryIssue { return issue }
        let e = error as NSError
        let kind: Kind
        switch (e.domain, e.code) {
        case (NSCocoaErrorDomain, NSFileReadNoSuchFileError), (NSCocoaErrorDomain, NSFileNoSuchFileError),
             (NSPOSIXErrorDomain, Int(ENOENT)), ("NSFileProviderErrorDomain",-1005): kind = .missing
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError), (NSPOSIXErrorDomain,Int(EACCES)), (NSPOSIXErrorDomain,Int(EPERM)),
             ("NSFileProviderErrorDomain",-1000): kind = .unreadable
        default: kind = .provider
        }
        return DirectoryIssue(kind:kind,item:item,underlying:e)
    }
    static func safeMessage(_ error: Error) -> String {
        if error is DirectoryIssue || error is MissingProjectEntry || error is RuntimeIssue || error is FolderAccessIssue {
            return error.localizedDescription
        }
        return reading(error,item:"项目目录").localizedDescription
    }
}

struct DirectoryEvent: Codable, Identifiable {
    let id: UUID
    let request: UUID
    let purpose: String
    let stage: String
    let milliseconds: Int
    let detail: String
    let domain: String?
    let code: Int?
    var line: String {
        let error = domain.map { " \($0) \(code ?? 0)" } ?? ""
        return "\(request.uuidString) \(purpose) \(stage) +\(milliseconds)ms \(detail)" + error
    }
}

final class DirectoryJournal: @unchecked Sendable {
    static let shared = DirectoryJournal()
    static let changed = Notification.Name("void.directoryDiagnostics")
    private let lock = NSLock()
    private let key = "void.directoryDiagnostics.v1"
    private let logger = Logger(subsystem:"app.chkf.void",category:"directory")
    private var entries: [DirectoryEvent]
    init() {
        entries = UserDefaults.standard.data(forKey:key).flatMap { try? JSONDecoder().decode([DirectoryEvent].self,from:$0) } ?? []
    }
    func append(_ entry: DirectoryEvent) {
        lock.lock()
        entries.append(entry)
        entries = Array(entries.suffix(180))
        if let bytes = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(bytes,forKey:key) }
        lock.unlock()
        logger.info("\(entry.line, privacy: .public)")
        DispatchQueue.main.async { NotificationCenter.default.post(name:Self.changed,object:nil) }
    }
    func recent() -> [DirectoryEvent] {
        lock.lock(); defer { lock.unlock() }; return entries
    }
}

struct DirectoryTrace: Sendable {
    let id: UUID
    let purpose: String
    private let began = ProcessInfo.processInfo.systemUptime
    init(_ purpose: String, id: UUID = UUID()) { self.purpose = purpose; self.id = id }
    func event(_ stage: String, _ detail: String = "", error: Error? = nil) {
        let native = (error as? DirectoryIssue)?.underlying ?? error.map { $0 as NSError }
        DirectoryJournal.shared.append(DirectoryEvent(id:UUID(),request:id,purpose:purpose,stage:stage,
            milliseconds:Int((ProcessInfo.processInfo.systemUptime - began)*1000),detail:detail,domain:native?.domain,code:native?.code))
    }
    static func measuring<T>(_ trace: Self?, _ stage: String, _ detail: String, _ body: () throws -> T) throws -> T {
        trace?.event(stage + ".begin",detail)
        do {
            let value = try body()
            trace?.event(stage + ".end",detail + " OK"); return value
        } catch { trace?.event(stage + ".end",detail + " 失败",error:error); throw error }
    }
    static func leaf(_ url: URL) -> String {
        String(url.lastPathComponent.components(separatedBy:.controlCharacters).joined(separator:" ").prefix(100))
    }
}

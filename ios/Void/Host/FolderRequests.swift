import Combine
import Foundation

enum FolderPurpose: Equatable {
    case create(String), importFolder
    var name: String {
        switch self {
        case .create: return "create"
        case .importFolder: return "import"
        }
    }
}

struct FolderRequest: Identifiable {
    let trace: DirectoryTrace
    var id: UUID { trace.id }
    let purpose: FolderPurpose
    let origin: UUID?
    let commit = DirectoryCommit()
}

@MainActor
final class FolderRequests: ObservableObject {
    enum Phase { case idle, presenting, processing, succeeded, failed, cancelled }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var request: FolderRequest?
    @Published private(set) var ready = false
    @Published private(set) var message = ""
    private var task: Task<Void,Never>?
    private var pickerClosed = false
    private var presented = false
    var active: Bool { phase == .presenting || phase == .processing }
    var failureMessage: String? { phase == .failed ? HostLanguage.text(message) : nil }
    var process: ((FolderRequest,URL) async throws -> String)?

    @discardableResult
    func begin(_ purpose: FolderPurpose, origin: UUID?, afterSheet: Bool = false) -> FolderRequest {
        if let request, active { return request }
        let r = FolderRequest(trace:DirectoryTrace(purpose.name),purpose:purpose,origin:origin)
        request = r; pickerClosed = false; presented = false; ready = !afterSheet
        phase = .presenting; message = "正在打开文件选择器"
        r.trace.event("picker.request")
        return r
    }
    func sheetClosed() { if phase == .presenting && !pickerClosed { ready = true } }
    func didPresent(_ id: UUID) {
        guard let r = request, r.id == id, phase == .presenting, ready, !presented else { return }
        presented = true; r.trace.event("picker.present")
        message = "等待系统文件选择器返回目录"
    }
    func pickerFailed(_ id: UUID, _ error: Error) {
        guard let r = request, r.id == id, phase == .presenting else { return }
        let system = error as NSError
        if error is CancellationError || (system.domain == NSCocoaErrorDomain && system.code == NSUserCancelledError) {
            pickerCancelled(id)
            return
        }
        dismissed(id)
        finish(r,.failed,DirectoryIssue.safeMessage(error),error:error)
    }
    func picked(_ id: UUID, _ urls: [URL]) {
        guard let r = request, r.id == id, phase == .presenting else { return }
        r.trace.event("picker.didPick","count=\(urls.count)" + (urls.first.map { " " + DirectoryTrace.leaf($0) } ?? ""))
        dismissed(id)
        guard urls.count == 1, let url = urls.first else {
            finish(r,.failed,"系统文件选择器未返回唯一目录",error:DirectoryIssue(kind:.emptySelection,item:"")); return
        }
        start(r,url:url)
    }
    func dismissed(_ id: UUID) {
        guard let r = request, r.id == id, !pickerClosed else { return }
        // Files can dismiss the dialog before delivering the selected URL or cancellation.
        pickerClosed = true
        ready = false
        r.trace.event("picker.dismiss")
    }
    func pickerCancelled(_ id: UUID) {
        guard phase == .presenting else { return }
        cancel(id)
    }
    func cancel(_ id: UUID) {
        guard let r = request, r.id == id, active else { return }
        guard r.commit.cancel() else { message = "正在保存已确认的目录操作"; return }
        if phase == .presenting { dismissed(id); r.trace.event("picker.cancel") }
        task?.cancel()
        finish(r,.cancelled,"已取消目录操作",error:CancellationError())
    }
    func changeProject(to id: UUID?) {
        guard let request else { return }
        if !active { clearResult() }
        else if request.origin != id { cancel(request.id) }
    }
    private func start(_ r: FolderRequest, url: URL) {
        phase = .processing; message = "正在检查目录授权和项目文件"
        task = Task {
            do {
                guard let process else { throw DirectoryIssue(kind:.provider,item:"目录操作") }
                let lease = try await DirectoryIO.run(trace: r.trace) { _ in SelectionLease(url) }
                defer { withExtendedLifetime(lease) {} }
                try Task.checkCancellation()
                let text = try await process(r,url)
                try Task.checkCancellation()
                guard request?.id == r.id && phase == .processing else { return }
                finish(r,.succeeded,text)
            } catch {
                guard request?.id == r.id && phase == .processing else { return }
                if error is CancellationError { finish(r,.cancelled,"已取消目录操作",error:error) }
                else { finish(r,.failed,DirectoryIssue.safeMessage(error),error:error) }
            }
        }
    }
    private func finish(_ r: FolderRequest, _ state: Phase, _ text: String, error: Error? = nil) {
        ready = false; phase = state; message = text; task = nil
        r.trace.event(r.purpose.name + ".result",state == .succeeded ? "OK" : (state == .cancelled ? "取消" : "失败"),error:error)
    }
    func updateProgress() {
        guard phase == .processing, let request,
              let stage = DirectoryJournal.shared.recent().last(where:{ $0.request == request.id })?.stage else { return }
        let status: String
        switch stage {
        case "import.copy": status = "正在将项目复制到 void 文稿"
        case "grant.begin","grant.resolve": status = "正在等待目录授权或文件协调"
        case "grant.accessor","scan.begin": status = "正在读取项目清单和源码"
        default: return
        }
        if message != status { message = status }
    }
    func clearResult() { if !active { phase = .idle; message = ""; request = nil } }
}

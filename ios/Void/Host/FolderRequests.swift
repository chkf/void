import Combine
import Foundation

enum FolderPurpose: Equatable {
    case create(String,ProjectTemplate), importFolder, reconnect(UUID), local
    var name: String {
        switch self { case .create:return "create"; case .importFolder:return "import"; case .reconnect:return "reconnect"; case .local:return "local" }
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
    enum Phase { case idle, presenting, selected, processing, succeeded, failed, cancelled }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var request: FolderRequest?
    @Published private(set) var ready = false
    @Published private(set) var message = ""
    private var selection: SelectionLease?
    private var task: Task<Void,Never>?
    private var pickerClosed = false
    private var presented = false
    var active: Bool { [.presenting,.selected,.processing].contains(phase) }
    var process: ((FolderRequest,URL) async throws -> String)?

    @discardableResult
    func begin(_ purpose: FolderPurpose, origin: UUID?, afterSheet: Bool = false) -> FolderRequest {
        if let request, active { return request }
        let r = FolderRequest(trace:DirectoryTrace(purpose.name),purpose:purpose,origin:origin)
        request = r; selection = nil; pickerClosed = false; presented = false; ready = !afterSheet
        phase = .presenting; message = "正在打开文件选择器"
        r.trace.event(purpose == .local ? "local.request" : "picker.request")
        if purpose == .local {
            ready = false; pickerClosed = true
            start(r,url:FolderGrant.documents)
        }
        return r
    }
    func sheetClosed() { if phase == .presenting { ready = true } }
    func didPresent(_ id: UUID) {
        guard let r = request, r.id == id, phase == .presenting, !presented else { return }
        presented = true; r.trace.event("picker.present")
        message = "等待系统文件选择器返回目录"
    }
    func picked(_ id: UUID, _ urls: [URL]) {
        guard let r = request, r.id == id, phase == .presenting else { return }
        r.trace.event("picker.didPick","count=\(urls.count)" + (urls.first.map { " " + DirectoryTrace.leaf($0) } ?? ""))
        guard urls.count == 1, let url = urls.first else {
            finish(r,.failed,"系统文件选择器未返回唯一目录",error:DirectoryIssue(kind:.emptySelection,item:"")); return
        }
        selection = SelectionLease(url)
        ready = false; phase = .selected; message = "已选中目录，正在关闭选择器"
    }
    func dismissed(_ id: UUID) {
        guard let r = request, r.id == id, !pickerClosed else { return }
        pickerClosed = true; r.trace.event("picker.dismiss",phase == .presenting ? "未收到选择回调" : "")
        if phase == .presenting { cancel(id); return }
        if phase == .selected, let lease = selection { start(r,url:lease.url) }
    }
    func cancel(_ id: UUID) {
        guard let r = request, r.id == id, active else { return }
        guard r.commit.cancel() else { return }
        if phase == .presenting || phase == .selected { r.trace.event("picker.cancel") }
        task?.cancel()
        finish(r,.cancelled,"已取消目录操作",error:CancellationError())
    }
    func changeProject(to id: UUID?) {
        if let r = request, active, r.origin != id {
            if phase == .processing && !r.commit.cancel() {
                finish(r,.succeeded,"目录操作已保存")
            } else { cancel(r.id) }
        }
    }
    private func start(_ r: FolderRequest, url: URL) {
        phase = .processing; message = "正在检查目录授权和项目文件"
        let lease = selection
        task = Task {
            defer { withExtendedLifetime(lease) {} }
            do {
                guard let process else { throw DirectoryIssue(kind:.provider,item:"目录操作") }
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
        ready = false; selection = nil; phase = state; message = text; task = nil
        r.trace.event(r.purpose.name + ".result",state == .succeeded ? "OK" : (state == .cancelled ? "取消" : "失败"),error:error)
    }
    func clearResult() { if !active { phase = .idle; message = ""; request = nil } }
}

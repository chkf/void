import SwiftUI
import WebKit

@MainActor
final class ProjectPage: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    let id = UUID()
    let product: Product
    let view: WKWebView
    let sdk: SDKSession
    @Published private(set) var nodes: [NativeNode] = []
    @Published private(set) var revision = 0
    private(set) var acknowledged = 0
    private var eventSequence = 0
    private let server: ResourceServer
    private var base: URL?
    private var valid = true
    private var ready = false
    private var timeout: Task<Void,Never>?
    private var lastProgress = ContinuousClock.now
    private var sawDocument = false
    private var firstSDKMethod: String?
    private var receivedTree = false
    private var newestTree = 0
    private var decoding: Task<NativeCommit,Error>?
    private let mounted = SDKWait<Void>()
    private(set) var failure: String?
    private(set) var displayed = false
    private let trace: DirectoryTrace?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?

    init(product: Product, record: ProjectRecord, storage: URL, permissions: [String], networkHosts: [String], trace: DirectoryTrace? = nil) throws {
        self.product = product
        self.trace = trace
        sdk = SDKSession(record: record, storage: storage, permissions: permissions, networkHosts: networkHosts)
        server = try ResourceServer(files: product.files)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let startup = """
        (() => {
          const call = (method, params) => window.webkit.messageHandlers.voidRPC.postMessage({version:1,id:crypto.randomUUID(),method,params});
          let failed = false;
          addEventListener('error', e => {
            failed = true;
            call('runtime.error', {message: String(e.message || '资源加载失败')});
          }, true);
          addEventListener('unhandledrejection', e => { failed = true; call('runtime.error',{message:String(e.reason)}); });
          addEventListener('load', () => { if (!failed) call('runtime.ready', {}); }, {once:true});
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: startup, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        sdk.ui.anchor = view
        sdk.events.deliver = { [weak self] id, name, value in
            guard let self, self.valid else { return }
            self.view.callAsyncJavaScript("window.__voidNativeEvent?.(event)", arguments: ["event": ["id":id, "type":name, "data":value]], in: nil, in: .page) { _ in }
        }
        view.navigationDelegate = self
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "voidRPC")
    }

    func start() async throws {
        let base = try await server.start()
        guard valid else { throw CancellationError() }
        self.base = base
        progress("page.load")
        view.load(URLRequest(url:base.appendingPathComponent(product.entry)))
        timeout = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(1)) } catch { return }
                guard let self, self.valid, !self.ready else { return }
                if self.sdk.ui.isPresenting { self.lastProgress = .now; continue }
                let limit: Duration = self.sdk.hasPendingRequests ? .seconds(120) : .seconds(60)
                if self.lastProgress.duration(to:.now) >= limit {
                    self.trace?.event("page.firstFrameTimeout")
                    let step = self.receivedTree ? "处理原生控件" : (self.sawDocument ? "页面已加载，仍在等待项目提交首屏" : "网页尚未加载完成")
                    self.reportFailure("等待项目首屏超时 · " + step)
                    return
                }
            }
        }
    }

    func stop() {
        guard valid else { return }
        valid = false
        decoding?.cancel()
        mounted.finish(.failure(CancellationError()))
        sdk.close()
        timeout?.cancel()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "voidRPC", contentWorld: .page)
        view.stopLoading()
        view.navigationDelegate = nil
        onReady = nil
        onFailure = nil
        server.stop()
    }

    private func contains(_ url: URL?) -> Bool {
        guard valid, let url, let base else { return false }
        return url.scheme == base.scheme && url.host == base.host && url.port == base.port && url.path.hasPrefix("/" + base.lastPathComponent + "/")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.targetFrame?.isMainFrame == true && contains(action.request.url) ? .allow : .cancel)
    }

    private func progress(_ stage: String) {
        guard valid, !ready else { return }
        lastProgress = .now
        trace?.event(stage)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { progress("page.navigationCommitted") }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { progress("page.navigationFinished") }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard valid else { return }
        trace?.event("page.processTerminated")
        reportFailure("项目的 WebKit 进程已终止，可在管理中重新预览")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    private func navigationFailed(_ error: Error) {
        guard valid else { return }
        trace?.event("page.navigationFailed",error:error)
        let e = error as NSError
        reportFailure("项目页面加载失败（\(e.domain) \(e.code)）")
    }

    private func reportFailure(_ detail: String) {
        failure = detail
        mounted.finish(.failure(RuntimeIssue(detail)))
        onFailure?(detail)
    }

    func didDisplay() {
        guard valid, ready, !displayed, failure == nil else { return }
        displayed = true
        trace?.event("page.firstFrame")
        mounted.finish(.success(()))
    }

    func waitForDisplay() async throws {
        let deadline = Task {
            do { try await Task.sleep(for:.seconds(20)) } catch { return }
            mounted.finish(.failure(RuntimeIssue("首屏已准备好，但尚未显示在项目窗口中")))
        }
        defer { deadline.cancel() }
        try await mounted.value()
    }

    private func confirm() {
        if !ready {
            progress("page.contentReady")
            ready = true
            timeout?.cancel()
            onReady?()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let body = message.body as? [String: Any]
        let id = body?["id"] as? String ?? ""
        func fail(_ code: String, _ detail: String) {
            replyHandler(["id": id, "result": ["success": false, "error": ["code": code, "message": detail]]], nil)
        }
        guard message.webView === view, message.frameInfo.isMainFrame, contains(message.frameInfo.request.url) else {
            fail("INVALID_SESSION", "会话来源无效"); return
        }
        guard body?["version"] as? Int == 1 else { fail("UNSUPPORTED_VERSION", "不支持的协议版本"); return }
        guard UUID(uuidString: id) != nil, let method = body?["method"] as? String, let params = body?["params"] as? [String: Any]
        else { fail("INVALID_PARAMS", "请求格式无效"); return }
        func success() { replyHandler(["id":id, "result":["success":true,"data":NSNull()]],nil) }
        switch method {
        case "ui.commit":
            guard product.mode == .native else { fail("INVALID_SESSION", "此页面使用 Web 模式"); return }
            do {
                let number = try NativeCommit.counter(params["revision"],minimum:1)
                guard number > newestTree else { success(); return }
                newestTree = number
                if !receivedTree {
                    receivedTree = true
                    progress("page.nativeCommitReceived")
                }
                decoding?.cancel()
                let task = Task.detached(priority:.userInitiated) { try NativeCommit(message:params) }
                decoding = task
                Task { @MainActor in
                    defer { if newestTree == number { decoding = nil } }
                    do {
                        let commit = try await task.value
                        guard valid else { fail("INVALID_SESSION","页面已关闭"); return }
                        if newestTree == number {
                            acknowledged = commit.eventSequence
                            nodes = commit.nodes
                            revision = commit.revision
                            confirm()
                        }
                        success()
                    } catch is CancellationError { success() }
                    catch {
                        fail("INVALID_TREE",error.localizedDescription)
                        if valid && newestTree == number { reportFailure(error.localizedDescription) }
                    }
                }
            } catch { fail("INVALID_TREE",error.localizedDescription); reportFailure(error.localizedDescription) }
            return
        case "runtime.ready":
            guard params.isEmpty else { fail("INVALID_PARAMS", "ready 没有参数"); return }
            if !sawDocument { sawDocument = true; progress("page.documentLoaded") }
            if product.mode == .web { confirm() }
        case "runtime.error":
            guard let message = params["message"] as? String else { fail("INVALID_PARAMS", "缺少错误消息"); return }
            trace?.event("page.scriptError")
            reportFailure(String(message.prefix(2048)))
        case "sdk.cancel":
            guard let request = params["id"] as? String else { fail("INVALID_PARAMS", "缺少请求标识"); return }
            sdk.cancel(request)
        default:
            let parts = method.split(separator:".")
            let first = !ready && firstSDKMethod == nil && parts.count == 2 &&
                SDKSession.methods[String(parts[0])]?[String(parts[1])] != nil
            if first { firstSDKMethod = method; progress("page.sdkBegin"); trace?.event("page.sdkMethod",method) }
            sdk.start(id:id,method:method,params:params) { [weak self] value,error in
                if first { self?.progress("page.sdkReturned") }
                replyHandler(value,error)
            }
            return
        }
        success()
    }

    @discardableResult
    func event(_ id: String, name: String, value: Any) -> Int {
        guard valid else { return eventSequence }
        eventSequence += 1
        let event: [String: Any] = ["id": id, "name": name, "value": value, "sequence": eventSequence, "revision":revision]
        view.callAsyncJavaScript("window.__voidEvent(event)", arguments: ["event": event], in: nil, in: .page) { [weak self] result in
            if case let .failure(error) = result, self?.valid == true { self?.onFailure?(error.localizedDescription) }
        }
        return eventSequence
    }
}

// Observe a display refresh after the visible SwiftUI surface has a window and layout.
@MainActor
struct PageDisplayProbe: UIViewRepresentable {
    let page: ProjectPage
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.page = page; view.arm() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.disarm() }

    final class Probe: UIView {
        weak var page: ProjectPage?
        private var link: CADisplayLink?
        private var ticks = 0
        override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { disarm() } else { arm() } }
        override func layoutSubviews() { super.layoutSubviews(); arm() }
        func arm() {
            guard link == nil, let page, !page.displayed, window != nil, !bounds.isEmpty else { return }
            let next = CADisplayLink(target:self,selector:#selector(tick))
            link = next
            next.add(to:.main,forMode:.common)
        }
        @objc private func tick() {
            guard window != nil, !bounds.isEmpty else { disarm(); return }
            ticks += 1
            if ticks == 2 { disarm(); page?.didDisplay() }
        }
        func disarm() { link?.invalidate(); link = nil; ticks = 0 }
    }
}

@MainActor
struct ProjectSurface: UIViewRepresentable {
    let webView: WKWebView
    init(page: ProjectPage) { webView = page.view }
    init(compiler: CompilerPage) { webView = compiler.view }
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

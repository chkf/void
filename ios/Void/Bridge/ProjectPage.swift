import SwiftUI
import WebKit

@MainActor
final class ProjectPage: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    let id = UUID()
    let product: Product
    let view: WKWebView
    let sdk: SDKSession
    @Published private var tree: NativeCommit?
    var nodes: [NativeNode] { tree?.nodes ?? [] }
    var revision: Int { tree?.revision ?? 0 }
    var acknowledged: Int { tree?.eventSequence ?? 0 }
    var uiVersion: Int { tree?.uiVersion ?? 1 }
    var hasTabNavigation: Bool { tree?.hasTabs == true }
    private var priorActions = [String: NativeAction]()
    private var priorRevision = 0
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
    private var attached = false
    private let trace: DirectoryTrace?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onOpenManagement: (() -> Void)?

    init(product: Product, record: ProjectRecord, storage: URL, permissions: [String], networkHosts: [String], trace: DirectoryTrace? = nil) throws {
        self.product = product
        self.trace = trace
        sdk = SDKSession(record: record, storage: storage, permissions: permissions, networkHosts: networkHosts, trace:trace)
        server = try ResourceServer(files: product.files)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let startup = """
        (() => {
          globalThis.__voidNativeUIVersion = 2;
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
        onOpenManagement = nil
        server.stop()
    }

    private func contains(_ url: URL?) -> Bool {
        guard valid, let url, let base else { return false }
        return url.scheme == base.scheme && url.host == base.host && url.port == base.port && url.path.hasPrefix("/" + base.lastPathComponent + "/")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.request.url?.absoluteString == "void://project/management" {
            decisionHandler(.cancel)
            if product.mode == .web, action.navigationType == .linkActivated, action.sourceFrame.isMainFrame,
               contains(action.sourceFrame.request.url), action.targetFrame?.isMainFrame == true {
                onOpenManagement?()
            }
            return
        }
        decisionHandler(action.targetFrame?.isMainFrame == true && contains(action.request.url) ? .allow : .cancel)
    }

    private func progress(_ stage: String, _ detail: String = "") {
        guard valid, !ready else { return }
        lastProgress = .now
        trace?.event(stage,detail)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { progress("page.navigationCommitted") }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { progress("page.navigationFinished") }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard valid else { return }
        trace?.event("page.processTerminated")
        reportFailure("项目的 WebKit 进程已终止，可在「设置」的「项目管理」中重新预览")
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

    func surfaceAttached() {
        guard valid, ready, !attached else { return }
        attached = true
        trace?.event("page.surfaceAttached")
    }

    func didDisplay(in window: UIWindow) -> Bool {
        guard valid, ready, !displayed, failure == nil, view.window === window else { return displayed }
        displayed = true
        trace?.event("page.firstFrame")
        mounted.finish(.success(()))
        return true
    }

    func waitForDisplay() async throws {
        let deadline = Task {
            do { try await Task.sleep(for:.seconds(20)) } catch { return }
            trace?.event("page.displayTimedOut", view.window == nil ? "页面未附着到窗口" : "尚未收到窗口刷新")
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
                            guard commit.eventSequence >= acknowledged, commit.eventSequence <= eventSequence else {
                                throw RuntimeIssue("原生界面确认的事件序号无效")
                            }
                            priorRevision = revision
                            priorActions = tree?.actions ?? [:]
                            tree = commit
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
            let scope = parts.count == 2 ? SDKSession.methods[String(parts[0])]?[String(parts[1])] : nil
            let first = !ready && firstSDKMethod == nil && scope != nil
            if first {
                firstSDKMethod = method
                progress("page.sdkMethod",method)
                if let scope, !scope.isEmpty, sdk.declared.contains(scope), sdk.access.decision(scope,project:sdk.record.id) == nil {
                    progress("page.sdkConsentPending")
                }
            }
            sdk.start(id:id,method:method,params:params) { [weak self] value,error in
                if first {
                    let result = (value as? [String:Any])?["result"] as? [String:Any]
                    self?.progress("page.sdkReturned",result?["success"] as? Bool == true ? "成功" : "失败")
                }
                replyHandler(value,error)
            }
            return
        }
        success()
    }

    @discardableResult
    func event(_ id: String, name: String, value: Any, displayedRevision: Int? = nil) -> Int {
        let displayed = displayedRevision ?? revision
        guard valid, tree?.actions[id]?.accepts(name, value) == true,
              displayed == revision || (displayed == priorRevision && priorActions[id]?.accepts(name, value) == true)
        else { return 0 }
        eventSequence += 1
        let event: [String: Any] = ["id":id,"name":name,"value":value,"sequence":eventSequence,"revision":displayed]
        view.callAsyncJavaScript("window.__voidEvent(event)", arguments: ["event": event], in: nil, in: .page) { [weak self] result in
            if case let .failure(error) = result, self?.valid == true { self?.onFailure?(error.localizedDescription) }
        }
        return eventSequence
    }
}

// This view owns the WebKit session for the page's entire SwiftUI lifetime.
// The native form and this surface share the same layout pass and window.
@MainActor
struct ProjectSurface: UIViewRepresentable {
    let webView: WKWebView
    private let showing: ProjectPage?

    init(page: ProjectPage, visible: Bool) {
        webView = page.view
        showing = visible ? page : nil
    }
    init(compiler: CompilerPage) { webView = compiler.view; showing = nil }

    func makeUIView(context: Context) -> Holder { Holder() }
    func updateUIView(_ holder: Holder, context: Context) {
        holder.mount(webView, showing:showing)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Holder, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by:CGSize(width:1,height:1))
    }
    static func dismantleUIView(_ view: Holder, coordinator: ()) { view.disarm() }

    final class Holder: UIView {
        private weak var webView: WKWebView?
        private weak var showing: ProjectPage?
        private var link: CADisplayLink?
        private var ticks = 0

        func mount(_ view: WKWebView, showing page: ProjectPage?) {
            if view.superview !== self {
                webView?.removeFromSuperview()
                webView = view
                view.frame = bounds
                addSubview(view)
            }
            if showing !== page { disarm(); showing = page }
            arm()
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { disarm() } else { arm() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            webView?.frame = bounds
            arm()
        }
        private func arm() {
            guard link == nil, let page = showing, !page.displayed,
                  let window, webView?.window === window, !bounds.isEmpty else { return }
            page.surfaceAttached()
            let next = CADisplayLink(target:self,selector:#selector(tick))
            link = next
            next.add(to:.main,forMode:.common)
        }
        @objc private func tick() {
            guard let page = showing, let window, webView?.window === window, !bounds.isEmpty else { disarm(); return }
            ticks = min(2,ticks + 1)
            if ticks == 2, page.didDisplay(in:window) { disarm() }
        }
        func disarm() { link?.invalidate(); link = nil; ticks = 0 }
    }
}

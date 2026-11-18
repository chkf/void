import Foundation
import WebKit

struct Product: Codable {
    let entry: String
    var files: [String: Data]
    let mode: UIMode
    let revision: String
}

enum Toolchain {
    static func read(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource:"Toolchain",withExtension:nil) else { throw RuntimeIssue("宿主缺少离线构建工具") }
        return try Data(contentsOf:url.appendingPathComponent(name),options:.mappedIfSafe)
    }
}

@MainActor
final class CompilerPage: NSObject, WKNavigationDelegate {
    let view: WKWebView
    private let loaded = SDKWait<Void>()
    private let output = SDKWait<[String:Any]>()
    private var closed = false

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        view = WKWebView(frame:.zero,configuration:config)
        super.init()
        view.navigationDelegate = self
    }

    private func wait<T>(_ signal: SDKWait<T>, timeout: Duration, stage: String) async throws -> T {
        let deadline = Task {
            do { try await Task.sleep(for:timeout) } catch { return }
            signal.finish(.failure(RuntimeIssue(stage + "超时，已停止本次编译")))
        }
        defer { deadline.cancel() }
        return try await signal.value()
    }

    func load(_ url: URL, timeout: Duration = .seconds(45)) async throws {
        try Task.checkCancellation()
        view.load(URLRequest(url:url))
        try await wait(loaded,timeout:timeout,stage:"启动离线编译器")
    }

    func compile(_ input: [String:Any], timeout: Duration = .seconds(120)) async throws -> [String:Any] {
        try Task.checkCancellation()
        view.callAsyncJavaScript("return await buildProject(input)",arguments:["input":input],in:nil,in:.page) { [weak self] result in
            guard let self, !self.closed else { return }
            self.output.finish(result.flatMap { value in
                guard let dictionary = value as? [String:Any] else { return .failure(RuntimeIssue("编译器返回了无效结果")) }
                return .success(dictionary)
            })
        }
        return try await wait(output,timeout:timeout,stage:"编译项目")
    }

    func stop() {
        guard !closed else { return }
        closed = true
        loaded.finish(.failure(CancellationError()))
        output.finish(.failure(CancellationError()))
        view.evaluateJavaScript("globalThis.cancelVoidBuild?.()",completionHandler:nil)
        view.stopLoading()
        view.navigationDelegate = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail(RuntimeIssue("系统已终止编译进程，可返回项目列表重试")) }
    private func fail(_ error: Error) { loaded.finish(.failure(error)); output.finish(.failure(error)) }
}

@MainActor
enum BuildEngine {
    static func build(_ snapshot: SourceSnapshot, willCompile: () async throws -> Void = {}) async throws -> Product {
        guard snapshot.info.mode != .swiftui else { throw RuntimeIssue("SwiftUI 源码由 Xcode 随宿主编译") }
        let resources = try await Task.detached {
            var result = [String:Data]()
            for name in ["index.html","compiler-client.js","compiler.js","esbuild.wasm","types.json","versions.json"] {
                result[name] = try Toolchain.read(name)
            }
            for (name,data) in snapshot.files { result["source/" + name] = data }
            return result
        }.value
        try Task.checkCancellation()
        let server = try ResourceServer(files:resources,compiler:true)
        defer { server.stop() }
        let base = try await server.start()
        let page = CompilerPage()
        defer { page.stop() }
        try await page.load(base.appendingPathComponent("index.html"))
        try await willCompile()
        let response = try await page.compile(["entry":snapshot.info.entry,"mode":snapshot.info.mode.rawValue,"paths":Array(snapshot.files.keys)])
        try Task.checkCancellation()
        if let error = response["failure"] as? String { throw RuntimeIssue(error) }
        guard let raw = response["files"] as? [String:String], let copied = response["copied"] as? [String:String],
              let entry = response["entry"] as? String, ProjectFiles.safePath(entry) else { throw RuntimeIssue("无效的构建资源表") }
        return try await Task.detached {
            var files = [String:Data]()
            for (key,source) in copied {
                guard ProjectFiles.safePath(key), let data = snapshot.files[source] else { throw RuntimeIssue("构建资源引用无效") }
                files[key] = data
            }
            for (key,text) in raw {
                guard ProjectFiles.safePath(key), files[key] == nil, let data = Data(base64Encoded:text) else { throw RuntimeIssue("构建资源编码无效") }
                files[key] = data
            }
            guard files[entry] != nil else { throw RuntimeIssue("构建产物缺少入口") }
            files["_void/libraries.js"] = try Toolchain.read("libraries.js")
            return Product(entry:entry,files:files,mode:snapshot.info.mode,revision:snapshot.revision)
        }.value
    }
}

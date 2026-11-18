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
        guard let url = Bundle.main.url(forResource: "Toolchain", withExtension: nil) else { throw RuntimeIssue("缺少离线构建工具，请运行 npm run prepare:ios") }
        return try Data(contentsOf: url.appendingPathComponent(name))
    }
}

@MainActor
private final class CompilerPage: NSObject, WKNavigationDelegate {
    let view: WKWebView
    var navigation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        view.navigationDelegate = self
    }

    func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            view.load(URLRequest(url: url))
        }
    }

    func finish(_ result: Result<Void, Error>) {
        navigation?.resume(with: result)
        navigation = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(RuntimeIssue("构建进程已终止"))) }
}

@MainActor
enum BuildEngine {
    static func build(_ snapshot: SourceSnapshot) async throws -> Product {
        let resources = try await Task.detached {
            try Dictionary(uniqueKeysWithValues: ["index.html", "compiler.js", "esbuild.wasm", "types.json", "versions.json"].map { ($0, try Toolchain.read($0)) })
        }.value
        let server = try ResourceServer(files: resources, compiler: true)
        defer { server.stop() }
        let base = try await server.start()
        let page = CompilerPage()
        defer { page.view.stopLoading() }
        try await page.load(base.appendingPathComponent("index.html"))
        try Task.checkCancellation()
        let input: [String: Any] = ["entry": snapshot.info.entry, "mode": snapshot.info.mode.rawValue,
                                    "files": snapshot.files.mapValues { $0.base64EncodedString() }]
        let value = try await page.view.callAsyncJavaScript(
            "try { return await buildProject(input) } catch(e) { return { failure: String(e.message || e) } }",
            arguments: ["input": input], in: nil, contentWorld: .page)
        guard let response = value as? [String: Any] else { throw RuntimeIssue("构建进程返回了无效结果") }
        if let error = response["failure"] as? String { throw RuntimeIssue(error) }
        guard let raw = response["files"] as? [String: String], let entry = response["entry"] as? String,
              raw[entry] != nil, ProjectFiles.safePath(entry) else { throw RuntimeIssue("构建产物缺少入口") }
        var files: [String: Data] = [:]
        for (key, text) in raw {
            guard ProjectFiles.safePath(key), let bytes = Data(base64Encoded: text) else { throw RuntimeIssue("无效的构建资源 " + key) }
            files[key] = bytes
        }
        files["_void/libraries.js"] = try Toolchain.read("libraries.js")
        return Product(entry: entry, files: files, mode: snapshot.info.mode, revision: snapshot.revision)
    }
}

import Foundation
import Network

private final class HTTPPolicy: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, URLSessionWebSocketDelegate, @unchecked Sendable {
    let hosts: Set<String>
    var progress: ((Int64, Int64) -> Void)?
    var connected: (() -> Void)?
    var connectionFailed: ((Error) -> Void)?
    init(_ hosts: Set<String>) { self.hosts = hosts }
    func allows(_ url: URL) -> Bool {
        guard ["https","http","wss","ws"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil else { return false }
        return hosts.contains(host)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(allows) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        progress?(totalBytesSent, totalBytesExpectedToSend)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) { connected?() }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        connectionFailed?(SDKFailure("SOCKET_CLOSED", "WebSocket 已关闭"))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { if let error { connectionFailed?(error) } }
}

@MainActor
final class NetworkSDK: SDKModule {
    private var sockets: [String:URLSessionWebSocketTask] = [:]
    private var sessions: [String:URLSession] = [:]

    private static func describe(_ path: NWPath) -> [String:Any] {
        ["connected":path.status == .satisfied,"expensive":path.isExpensive,"constrained":path.isConstrained,
         "interface":path.usesInterfaceType(.wifi) ? "wifi" : (path.usesInterfaceType(.cellular) ? "cellular" : "other")]
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        let events = s.events
        if method == "status" || method == "watchStatus" {
            let id = UUID().uuidString, monitor = NWPathMonitor(), first = SDKWait<[String:Any]>()
            monitor.pathUpdateHandler = { path in Task { @MainActor in
                let value = Self.describe(path)
                first.finish(.success(value))
                events.emit(id, "network.status", value)
            } }
            _ = events.add(id) { monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "void.network.status"))
            if method == "watchStatus" { return id }
            defer { events.stop(id) }
            return try await first.value()
        }
        if method == "sendSocket" || method == "closeSocket" {
            let id = try a.string("id")
            guard let socket = sockets[id] else { throw SDKFailure("NOT_FOUND","WebSocket 已关闭") }
            if method == "closeSocket" { events.stop(id) }
            else if a.values["base64"] != nil { try await socket.send(.data(a.data("base64"))) }
            else { try await socket.send(.string(a.string("text"))) }
            return NSNull()
        }
        let policy = HTTPPolicy(s.networkHosts)
        guard let url = URL(string: try a.string("url")), policy.allows(url) else { throw SDKFailure.denied("请在 app/manifest.json 的 networkHosts 中声明目标域名") }
        let scheme = url.scheme?.lowercased() ?? ""
        guard (method == "openSocket" ? ["ws","wss"] : ["https","http"]).contains(scheme) else { throw SDKFailure.invalid("url") }
        if method == "upload" { try await s.require("files.read") }
        if method == "download" { try await s.require("files.write") }
        let id = try a.string("progressId", UUID().uuidString)
        guard sessions[id] == nil else { throw SDKFailure("BUSY","请求标识已在使用") }
        let config = URLSessionConfiguration.ephemeral
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.urlCache = nil
        let timeout = try a.number("timeout", 60)
        guard (1...3600).contains(timeout) else { throw SDKFailure.invalid("timeout") }
        config.timeoutIntervalForRequest = timeout
        var request = URLRequest(url: url)
        if let headers = a.values["headers"] {
            guard let values = headers as? [String:String] else { throw SDKFailure.invalid("headers") }
            for (k,v) in values {
                guard !["host","connection","content-length","proxy-authorization"].contains(k.lowercased()), !k.contains("\n"), !k.contains("\r"), !v.contains("\r"), !v.contains("\n") else { throw SDKFailure.invalid("headers") }
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
        let http = URLSession(configuration: config, delegate: policy, delegateQueue: nil)
        sessions[id] = http
        policy.progress = { done, total in Task { @MainActor in events.emit(id,"network.progress",["completed":done,"total":total]) } }
        _ = events.add(id) { [weak self] in
            self?.sockets.removeValue(forKey: id)?.cancel(with: .goingAway, reason: nil)
            self?.sessions.removeValue(forKey: id)?.invalidateAndCancel()
        }
        var keepSocket = false
        defer { if !keepSocket { events.stop(id) } }
        if method == "openSocket" {
            let wait = SDKWait<Bool>()
            policy.connected = { Task { @MainActor in wait.finish(.success(true)) } }
            policy.connectionFailed = { error in Task { @MainActor in wait.finish(.failure(error)) } }
            let socket = http.webSocketTask(with: request)
            socket.maximumMessageSize = SDKFiles.maxChunk
            sockets[id] = socket
            socket.resume()
            _ = try await wait.value()
            keepSocket = true
            Task { @MainActor in
                do {
                    while socket.state == .running {
                        switch try await socket.receive() {
                        case .string(let text): events.emit(id, "network.message", ["text":text])
                        case .data(let data): events.emit(id, "network.message", ["base64":data.base64EncodedString()])
                        @unknown default: break
                        }
                    }
                } catch { events.emit(id,"network.closed",["code":socket.closeCode.rawValue,"message":error.localizedDescription]) }
                events.stop(id)
            }
            return id
        }
        request.httpMethod = try a.choice("method", ["GET","POST","PUT","PATCH","DELETE","HEAD"], method == "upload" ? "POST" : "GET")
        if let body = a.values["body"] as? String { request.httpBody = Data(body.utf8) }
        if a.values["base64"] != nil { request.httpBody = try a.data("base64") }
        func metadata(_ response: URLResponse) throws -> [String: Any] {
            guard let h = response as? HTTPURLResponse else { throw SDKFailure("NETWORK_ERROR","服务器响应无效") }
            let headers = Dictionary(uniqueKeysWithValues: h.allHeaderFields.map { (String(describing:$0.key), String(describing:$0.value)) })
            return ["status":h.statusCode, "headers":headers, "url":h.url?.absoluteString ?? url.absoluteString]
        }
        if method == "download" {
            let target = try a.string("to")
            let (file, response) = try await http.download(for: request, delegate: policy)
            try Task.checkCancellation()
            var meta = try metadata(response)
            guard (200..<300).contains(meta["status"] as? Int ?? 0) else { throw SDKFailure("HTTP_ERROR","下载失败，HTTP \(meta["status"] ?? "")") }
            try s.files.store(file, at: target)
            meta["path"] = target
            return meta
        }
        let data: Data, response: URLResponse
        if method == "upload" { (data,response) = try await http.upload(for: request, fromFile: s.files.input(a.string("path")), delegate: policy) }
        else {
            let (stream, result) = try await http.bytes(for: request, delegate: policy)
            var bytes = Data()
            for try await byte in stream {
                guard bytes.count < SDKFiles.maxChunk else { throw SDKFailure("TOO_LARGE","请用 download 保存大文件") }
                bytes.append(byte)
            }
            (data,response) = (bytes,result)
        }
        guard data.count <= SDKFiles.maxChunk else { throw SDKFailure("TOO_LARGE","响应超过大小限制") }
        var meta = try metadata(response)
        meta["base64"] = data.base64EncodedString()
        if let text = String(data:data, encoding:.utf8) { meta["text"] = text }
        return meta
    }
    func close() { for session in sessions.values { session.invalidateAndCancel() }; sessions.removeAll(); sockets.removeAll() }
}

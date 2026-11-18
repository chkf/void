import Foundation
import Network
import UniformTypeIdentifiers

/// 每个会话只有一个回环来源；请求只能命中此版本的不可变资源表。
final class ResourceServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "void.resources")
    private let token = UUID().uuidString.lowercased()
    private let files: [String: Data]
    private let compiler: Bool
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var startup: CheckedContinuation<URL, Error>?
    private var startupTimeout: DispatchWorkItem?
    private var started = false
    private var stopped = false

    init(files: [String: Data], compiler: Bool = false) throws {
        self.files = files
        self.compiler = compiler
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    func start() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                queue.async {
                    guard !self.started, !self.stopped else { continuation.resume(throwing:CancellationError()); return }
                    self.started = true
                    self.startup = continuation
                    let deadline = DispatchWorkItem { [weak self] in
                        self?.finishStartup(.failure(RuntimeIssue("启动本地预览服务超时")))
                        self?.stop()
                    }
                    self.startupTimeout = deadline
                    self.queue.asyncAfter(deadline:.now()+20,execute:deadline)
                    self.listener.stateUpdateHandler = { [weak self] state in self?.stateChanged(state) }
                    self.listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    self.listener.start(queue:self.queue)
                }
            }
        } onCancel: { self.stop() }
    }

    private func stateChanged(_ state: NWListener.State) {
        guard startup != nil else { return }
        switch state {
        case .ready:
            guard let port = listener.port,
                  let url = URL(string:"http://127.0.0.1:" + String(port.rawValue) + "/" + token + "/")
            else { finishStartup(.failure(RuntimeIssue("无法分配本地资源地址"))); return }
            finishStartup(.success(url))
        case .failed(let error), .waiting(let error): finishStartup(.failure(error))
        case .cancelled: finishStartup(.failure(CancellationError()))
        default: break
        }
    }

    private func finishStartup(_ result: Result<URL,Error>) {
        let waiting = startup
        startup = nil
        startupTimeout?.cancel()
        startupTimeout = nil
        waiting?.resume(with:result)
    }

    func stop() {
        queue.async {
            guard !self.stopped else { return }
            self.stopped = true
            self.finishStartup(.failure(CancellationError()))
            self.listener.cancel()
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.connections.removeValue(forKey: id)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(connection, bytes: Data())
    }

    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] chunk, _, done, error in
            guard let self, let chunk, error == nil else { connection.cancel(); return }
            let request = bytes + chunk
            if request.count > 16384 { connection.cancel(); return }
            if let end = request.range(of: Data("\r\n\r\n".utf8)),
               let headers = String(data: request[..<end.lowerBound], encoding: .utf8) {
                let response = self.respond(headers)
                if let body = response.body {
                    connection.send(content:response.headers,completion:.contentProcessed { error in
                        if error != nil { connection.cancel(); return }
                        connection.send(content:body,completion:.contentProcessed { _ in connection.cancel() })
                    })
                } else {
                    connection.send(content:response.headers,completion:.contentProcessed { _ in connection.cancel() })
                }
            } else if done { connection.cancel() }
            else { self.receive(connection, bytes: request) }
        }
    }

    static func byteRange(_ value: String, count: Int) -> Range<Int>? {
        guard count > 0, value.hasPrefix("bytes=") else { return nil }
        let parts = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else { return nil }
            return (count - min(count, suffix))..<count
        }
        guard let start = Int(parts[0]), start >= 0, start < count else { return nil }
        if parts[1].isEmpty { return start..<count }
        guard let last = Int(parts[1]), last >= start else { return nil }
        return start..<(min(count - 1, last) + 1)
    }

    private typealias Response = (headers: Data, body: Data?)
    private func respond(_ request: String) -> Response {
        let denied: Response = (Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),nil)
        let lines = request.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3, ["GET", "HEAD"].contains(first[0]), let port = listener.port else { return denied }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return denied }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { return denied }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let prefix = "/" + token + "/"
        guard headers["host"] == "127.0.0.1:" + String(port.rawValue),
              let raw = first[1].split(separator: "?", maxSplits: 1).first,
              let path = String(raw).removingPercentEncoding, path.hasPrefix(prefix) else { return denied }
        let name = String(path.dropFirst(prefix.count))
        guard ProjectFiles.safePath(name), let data = files[name] else { return denied }
        var range = 0..<data.count
        var status = "200 OK"
        var extra = ""
        if let value = headers["range"] {
            guard let selected = Self.byteRange(value, count: data.count) else {
                return (Data(("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */" + String(data.count) + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").utf8),nil)
            }
            range = selected
            status = "206 Partial Content"
            extra = "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)\r\n"
        }
        let ext = (name as NSString).pathExtension.lowercased()
        let mime = ["js": "text/javascript", "mjs": "text/javascript", "wasm": "application/wasm",
                    "css": "text/css", "html": "text/html", "htm": "text/html", "json": "application/json"][ext]
            ?? UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        let script = compiler ? "'self' 'wasm-unsafe-eval' 'unsafe-eval'" : "'self' 'unsafe-inline' 'wasm-unsafe-eval'"
        let policy = "default-src 'none'; script-src \(script); connect-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; media-src 'self' blob:; worker-src 'self' blob:; frame-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(range.count)\r\n" + extra
            + "Accept-Ranges: bytes\r\nContent-Security-Policy: \(policy)\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nCache-Control: private, max-age=31536000, immutable\r\nConnection: close\r\n\r\n"
        let body = first[0] == "GET" ? (range.count == data.count ? data : data[range]) : nil
        return (Data(head.utf8),body)
    }
}

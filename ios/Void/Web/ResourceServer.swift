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

    init(files: [String: Data], compiler: Bool = false) throws {
        self.files = files
        self.compiler = compiler
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            var waiting = true
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, waiting else { return }
                switch state {
                case .ready:
                    waiting = false
                    guard let port = self.listener.port,
                          let url = URL(string: "http://127.0.0.1:" + String(port.rawValue) + "/" + self.token + "/")
                    else { continuation.resume(throwing: RuntimeIssue("无法分配本地资源地址")); return }
                    continuation.resume(returning: url)
                case .failed(let error):
                    waiting = false
                    continuation.resume(throwing: error)
                case .cancelled:
                    waiting = false
                    continuation.resume(throwing: CancellationError())
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        queue.async {
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
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
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

    private func respond(_ request: String) -> Data {
        let denied = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
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
                return Data(("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */" + String(data.count) + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").utf8)
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
        var result = Data(head.utf8)
        if first[0] == "GET" { result.append(data[range]) }
        return result
    }
}

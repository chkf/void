import Foundation
import SQLite3
import ImageIO
import UIKit
import UniformTypeIdentifiers

private actor ProjectDatabase {
    let file: URL
    init(_ file: URL) { self.file = file }

    private func dbError(_ db: OpaquePointer?) -> SDKFailure { SDKFailure("DATABASE_ERROR", String(cString: sqlite3_errmsg(db))) }

    func run(_ method: String, _ args: SDKArgs) throws -> Any {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let e = dbError(db); sqlite3_close(db); throw e
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 4 * 1024 * 1024)
        sqlite3_limit(db, SQLITE_LIMIT_SQL_LENGTH, 128 * 1024)
        sqlite3_set_authorizer(db, { _, action, _, detail, _, _ in
            switch action {
            case SQLITE_ATTACH, SQLITE_DETACH, SQLITE_PRAGMA, SQLITE_CREATE_VTABLE, SQLITE_DROP_VTABLE: return SQLITE_DENY
            case SQLITE_FUNCTION:
                if let detail, ["load_extension","readfile","writefile","fts3_tokenizer"].contains(String(cString: detail).lowercased()) { return SQLITE_DENY }
            default: break
            }
            return SQLITE_OK
        }, nil)
        let deadline = UnsafeMutablePointer<TimeInterval>.allocate(capacity: 1)
        deadline.initialize(to: ProcessInfo.processInfo.systemUptime + 5)
        defer { sqlite3_progress_handler(db, 0, nil, nil); deadline.deinitialize(count: 1); deadline.deallocate() }
        sqlite3_progress_handler(db, 2000, { raw in
            guard let raw else { return 1 }
            return ProcessInfo.processInfo.systemUptime >= raw.assumingMemoryBound(to: TimeInterval.self).pointee ? 1 : 0
        }, deadline)
        func statement(_ a: SDKArgs, query: Bool) throws -> Any {
            let sql = try a.string("sql")
            guard !sql.utf8.contains(0) else { throw SDKFailure.invalid("sql") }
            var prepared: OpaquePointer?
            defer { sqlite3_finalize(prepared) }
            try sql.withCString { text in
                var rest: UnsafePointer<CChar>?
                guard sqlite3_prepare_v2(db, text, -1, &prepared, &rest) == SQLITE_OK, prepared != nil else { throw dbError(db) }
                guard rest.map({ String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else {
                    throw SDKFailure.invalid("每个 sql 只接受一条语句")
                }
            }
            let params = a.values["params"] as? [Any] ?? []
            guard params.count == Int(sqlite3_bind_parameter_count(prepared)) else { throw SDKFailure.invalid("params") }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (offset, value) in params.enumerated() {
                let index = Int32(offset + 1)
                let status: Int32
                switch value {
                case is NSNull: status = sqlite3_bind_null(prepared, index)
                case let text as String: status = sqlite3_bind_text(prepared, index, text, Int32(text.utf8.count), transient)
                case let n as NSNumber:
                    if CFNumberIsFloatType(n) { status = sqlite3_bind_double(prepared, index, n.doubleValue) }
                    else { status = sqlite3_bind_int64(prepared, index, n.int64Value) }
                case let obj as [String:String] where obj["base64"] != nil:
                    guard let bytes = Data(base64Encoded: obj["base64"]!) else { throw SDKFailure.invalid("params.base64") }
                    status = bytes.withUnsafeBytes { sqlite3_bind_blob(prepared, index, $0.baseAddress, Int32($0.count), transient) }
                default: throw SDKFailure.invalid("params")
                }
                guard status == SQLITE_OK else { throw dbError(db) }
            }
            if query && sqlite3_stmt_readonly(prepared) == 0 { throw SDKFailure.invalid("query 只接受读取语句") }
            var rows: [[String:Any]] = []
            var bytes = 0
            while true {
                let result = sqlite3_step(prepared)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw dbError(db) }
                if !query { continue }
                var row: [String:Any] = [:]
                for i in 0..<sqlite3_column_count(prepared) {
                    let key = String(cString: sqlite3_column_name(prepared, i))
                    bytes += Int(sqlite3_column_bytes(prepared, i))
                    guard bytes <= SDKFiles.maxChunk, rows.count < 1000 else { throw SDKFailure("TOO_LARGE", "请用 LIMIT 分页查询") }
                    switch sqlite3_column_type(prepared, i) {
                    case SQLITE_INTEGER: row[key] = sqlite3_column_int64(prepared, i)
                    case SQLITE_FLOAT: row[key] = sqlite3_column_double(prepared, i)
                    case SQLITE_TEXT:
                        let buffer = UnsafeBufferPointer(start: sqlite3_column_text(prepared, i), count: Int(sqlite3_column_bytes(prepared, i)))
                        row[key] = String(decoding: buffer, as: UTF8.self)
                    case SQLITE_BLOB:
                        let size = Int(sqlite3_column_bytes(prepared, i))
                        let data = sqlite3_column_blob(prepared, i).map { Data(bytes: $0, count: size) } ?? Data()
                        row[key] = ["base64":data.base64EncodedString()]
                    default: row[key] = NSNull()
                    }
                }
                rows.append(row)
            }
            if query { return rows }
            return ["changes":Int(sqlite3_changes(db)), "lastInsertId":sqlite3_last_insert_rowid(db)] as [String:Any]
        }
        guard method == "transaction" else { return try statement(args, query: method == "query") }
        guard let entries = args.values["statements"] as? [[String:Any]], !entries.isEmpty else { throw SDKFailure.invalid("statements") }
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw dbError(db) }
        do {
            let results = try entries.map { entry -> Any in
                let sql = try SDKArgs(entry).string("sql").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let first = sql.prefix { $0.isLetter }
                guard ["insert","update","delete","replace","create","drop","alter"].contains(String(first)) else { throw SDKFailure.invalid("transaction.sql") }
                return try statement(SDKArgs(entry), query: false)
            }
            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw dbError(db) }
            return results
        } catch { sqlite3_exec(db, "ROLLBACK", nil, nil, nil); throw error }
    }
}

@MainActor
final class GraphicsSDK: SDKModule {
    private var database: ProjectDatabase?

    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if ["execute","query","transaction"].contains(method) {
            let db = database ?? ProjectDatabase(s.storage.appendingPathComponent("Projects/" + s.record.id.uuidString + "/Database/project.sqlite"))
            database = db
            return try await db.run(method, a)
        }
        if method == "capabilities" {
            return ["imageFormats":["jpeg","png"],"sqlite":String(cString: sqlite3_libversion()),"maxChunkBytes":SDKFiles.maxChunk] as [String:Any]
        }
        let input = try s.files.input(a.string("path"))
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString:Any] else { throw SDKFailure("INVALID_MEDIA", "无法读取图像") }
        if method == "imageInfo" {
            return ["width":props[kCGImagePropertyPixelWidth] ?? 0, "height":props[kCGImagePropertyPixelHeight] ?? 0,
                    "type":CGImageSourceGetType(source) as String? ?? "", "frames":CGImageSourceGetCount(source)] as [String:Any]
        }
        let size = try a.int("maxDimension", 1600, range: 1...8192)
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:size]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw SDKFailure("INVALID_MEDIA","图像缩放失败") }
        let format = try a.choice("format", ["jpeg","png"], "jpeg")
        let target = try a.string("to")
        let tmp = try s.files.temp("image." + format)
        guard let output = CGImageDestinationCreateWithURL(tmp as CFURL, (format == "png" ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil) else { throw SDKFailure("MEDIA_ERROR", "无法创建图像") }
        let quality = try a.number("quality", 0.85)
        guard (0...1).contains(quality) else { throw SDKFailure.invalid("quality") }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw SDKFailure("MEDIA_ERROR", "图像编码失败") }
        try s.files.store(tmp, at: target)
        return target
    }
}

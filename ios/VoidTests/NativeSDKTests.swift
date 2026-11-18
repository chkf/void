import XCTest
@testable import VoidHost

@MainActor
final class NativeSDKTests: XCTestCase {
    private var parent: URL!
    private var storage: URL!
    private var record: ProjectRecord!
    private var sdk: SDKSession!
    private let permissions = ["files.read","files.write","database","network","graphics"]

    override func setUp() async throws {
        parent = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
        record = try await ProjectLibrary(base:storage).create(name:"SDK",parent:parent,template:.tsx)
        sdk = SDKSession(record:record,storage:storage,permissions:permissions,networkHosts:["127.0.0.1"])
        for permission in permissions { SDKConsent.shared.set(true,for:permission,project:record.id) }
    }
    override func tearDown() async throws {
        sdk?.close()
        if let record { for permission in permissions { SDKConsent.shared.set(nil,for:permission,project:record.id) } }
        if let parent { try? FileManager.default.removeItem(at:parent) }
        if let storage { try? FileManager.default.removeItem(at:storage) }
    }
    private func result(_ method: String, _ params: [String:Any] = [:], in session: SDKSession? = nil) async -> [String:Any] {
        await withCheckedContinuation { continuation in
            (session ?? sdk).start(id:UUID().uuidString,method:method,params:params) { reply, _ in
                continuation.resume(returning:(reply as? [String:Any])?["result"] as? [String:Any] ?? [:])
            }
        }
    }
    private func data(_ method: String, _ params: [String:Any] = [:], in session: SDKSession? = nil) async throws -> Any {
        let reply = await result(method,params,in:session)
        guard reply["success"] as? Bool == true, let value = reply["data"] else { throw RuntimeIssue(method + " " + String(describing:reply["error"])) }
        return value
    }
    private func error(_ result: [String:Any]) -> String? { (result["error"] as? [String:Any])?["code"] as? String }

    func testRegisteredPermissionsAndIsolatedFiles() async throws {
        XCTAssertEqual(SDKSession.methods.count,18)
        XCTAssertTrue(SDKSession.methods.values.flatMap(\.values).filter{!$0.isEmpty}.allSatisfy{SDKConsent.labels[$0] != nil})
        let path = "data/notes/a.txt"
        _ = try await data("fs.writeFile",["path":path,"data":"简"])
        _ = try await data("fs.appendFile",["path":path,"data":"体"])
        let read = try await data("fs.readFile",["path":path]) as? String
        XCTAssertEqual(read,"简体")
        _ = try await data("fs.copyFile",["path":path,"to":"private/nested/new.txt"])
        _ = try await data("fs.mkdir",["path":"cache/copied"])
        _ = try await data("fs.moveFile",["path":"private/nested/new.txt","to":"cache/copied/b.txt"])
        let metadata = try await data("fs.stat",["path":"cache/copied/b.txt"]) as? [String:Any]
        XCTAssertEqual(metadata?["size"] as? Int,6)
        let chunk = try await data("fs.readChunk",["path":path,"offset":3,"length":3]) as? String
        XCTAssertEqual(chunk,Data("体".utf8).base64EncodedString())
        let outside = await result("fs.readFile",["path":"data/../runtime.json"])
        XCTAssertEqual(error(outside),"PERMISSION_DENIED")
        let second = try await ProjectLibrary(base:storage).create(name:"另外的项目",parent:parent)
        let ownFiles = SDKFiles(record:second,storage:storage)
        XCTAssertEqual(try ownFiles.call("exists",SDKArgs(["path":path])) as? Bool,false)
        let denied = await result("contacts.search")
        XCTAssertEqual(error(denied),"NOT_DECLARED")
        SDKConsent.shared.set(false,for:"files.write",project:record.id)
        let blocked = await result("fs.deleteFile",["path":path])
        XCTAssertEqual(error(blocked),"PERMISSION_DENIED")
    }

    func testPersistentSQLAndRealCryptography() async throws {
        _ = try await data("graphics.execute",["sql":"CREATE TABLE notes(value TEXT)"])
        let insert: [String:Any] = ["sql":"INSERT INTO notes VALUES (?)","params":["数据"]]
        _ = try await data("graphics.transaction",["statements":[insert,insert]])
        let rejected = await result("graphics.transaction",["statements":[insert,["sql":"INSERT INTO absent VALUES (1)"]]])
        XCTAssertEqual(rejected["success"] as? Bool,false)
        let reopened = SDKSession(record:record,storage:storage,permissions:permissions,networkHosts:[])
        defer { reopened.close() }
        let rows = try await data("graphics.query",["sql":"SELECT value FROM notes"],in:reopened) as? [[String:String]]
        XCTAssertEqual(rows?.map{$0["value"]},["数据","数据"])
        let plain = Data("visible".utf8).base64EncodedString()
        let hash = try await data("security.hash",["data":plain]) as? String
        XCTAssertEqual(hash?.count,64)
        let bytes = try await data("security.random",["length":16]) as? String
        XCTAssertEqual(bytes.flatMap{Data(base64Encoded:$0)}?.count,16)
        let sealedValue = try await data("security.encrypt",["key":"test","data":plain])
        let sealed = try XCTUnwrap(sealedValue as? String)
        let decrypted = try await data("security.decrypt",["key":"test","data":sealed],in:reopened) as? String
        XCTAssertEqual(decrypted,plain)
        _ = try await data("security.setSecret",["key":"account","value":"值"])
        let secret = try await data("security.getSecret",["key":"account"]) as? String
        XCTAssertEqual(secret,"值")
        _ = try await data("security.deleteSecret",["key":"account"])
    }

    func testLocalNetworkDownloadAndDeviceAvailability() async throws {
        let bytes = Data("来自服务器".utf8)
        let server = try ResourceServer(files:["note.txt":bytes])
        defer { server.stop() }
        let url = try await server.start().appendingPathComponent("note.txt")
        let reply = try await data("network.request",["url":url.absoluteString]) as? [String:Any]
        XCTAssertEqual(reply?["status"] as? Int,200)
        XCTAssertEqual(reply?["base64"] as? String,bytes.base64EncodedString())
        _ = try await data("network.download",["url":url.absoluteString,"to":"data/download.txt"])
        let path = parent.appendingPathComponent("SDK/data/download.txt")
        XCTAssertEqual(try Data(contentsOf:path),bytes)
        let blocked = await result("network.request",["url":"https://not-declared.invalid/"])
        XCTAssertEqual(error(blocked),"PERMISSION_DENIED")
        let camera = try await data("camera.available") as? [String:Bool]
        XCTAssertNotNil(camera?["back"])
        let nfc = try await data("nfc.available")
        XCTAssertTrue(nfc is Bool)
        let health = try await data("health.authorization",["type":"steps"]) as? [String:String]
        XCTAssertEqual(health?["read"],"notDisclosed")
    }
}

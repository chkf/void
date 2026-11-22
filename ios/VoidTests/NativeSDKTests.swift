import AVFoundation
import UIKit
import XCTest
@testable import VoidHost

@MainActor
final class NativeSDKTests: XCTestCase {
    private var parent: URL!
    private var storage: URL!
    private var record: ProjectRecord!
    private var sdk: SDKSession!
    private let permissions = ["files.read","files.write","database","network","graphics","audio.play","video","notifications"]

    override func setUp() async throws {
        parent = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
        record = try await ProjectLibrary(base:storage).create(name:"SDK",parent:parent)
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

    func testClosingFirstConsentCancelsWithoutSavingADecision() async throws {
        let window = try await PreviewTestWindow(HostModel(storage:storage))
        defer { window.close() }
        let root = try XCTUnwrap(window.window.rootViewController)
        SDKConsent.shared.set(nil,for:"database",project:record.id)
        let directory = try record.grant.withRoot { $0 }
        let holding = expectation(description:"提供方占用原目录")
        let release = DispatchSemaphore(value:0)
        DispatchQueue.global().async {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt:directory,options:.forReplacing,error:&error) { _ in
                holding.fulfill()
                _ = release.wait(timeout:.now()+15)
            }
        }
        defer { release.signal() }
        await fulfillment(of:[holding],timeout:4)
        let scan = DirectoryTrace("verification-test")
        let library = ProjectLibrary(base:storage)
        let id = record.id
        let checking = Task { try await library.revision(id,trace:scan) }
        defer { checking.cancel() }
        let trace = DirectoryTrace("consent-test")
        let session = SDKSession(record:record,storage:storage,permissions:permissions,networkHosts:[],trace:trace)
        session.ui.anchor = root.view
        defer { session.close() }
        let query = Task { await self.result("graphics.query",["sql":"SELECT 1"],in:session) }
        let deadline = ContinuousClock.now + .seconds(8)
        while !(root.presentedViewController is UIAlertController) && ContinuousClock.now < deadline {
            try await Task.sleep(for:.milliseconds(30))
        }
        let alert = try XCTUnwrap(root.presentedViewController as? UIAlertController)
        let pending = DirectoryJournal.shared.recent().filter { $0.request == scan.id }
        XCTAssertFalse(pending.contains { $0.stage == "scan.end" })
        XCTAssertEqual(alert.actions.compactMap(\.title),["不允许","允许"])
        XCTAssertNil(SDKConsent.shared.decision("database",project:record.id))
        session.close()
        let reply = await query.value
        XCTAssertEqual(error(reply),"CANCELLED")
        XCTAssertNil(root.presentedViewController)
        XCTAssertNil(SDKConsent.shared.decision("database",project:record.id))
        XCTAssertEqual(SDKConsent.shared.decision("files.read",project:record.id),true)
        let events = DirectoryJournal.shared.recent().filter { $0.request == trace.id }
        XCTAssertEqual(events.map(\.stage),["sdk.consent.begin","sdk.consent.end"])
        XCTAssertEqual(events.last?.detail,"database CANCELLED")
        release.signal()
        let revision = try await checking.value
        XCTAssertFalse(revision.isEmpty)
        XCTAssertTrue(DirectoryJournal.shared.recent().contains { $0.request == scan.id && $0.stage == "scan.fingerprint" })
    }

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

    func testNativeImageAudioVideoAndNotificationCategories() async throws {
        let files = sdk.files
        let image = UIGraphicsImageRenderer(size:CGSize(width:60,height:40)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x:0,y:0,width:60,height:40))
        }
        let imageFile = try files.temp("image.png")
        try XCTUnwrap(image.pngData()).write(to:imageFile)
        try files.store(imageFile,at:"data/image.png")
        _ = try await data("graphics.processImage",["path":"data/image.png","to":"data/small.jpg","maxDimension":30])
        let size = try await data("graphics.imageInfo",["path":"data/small.jpg"]) as? [String:Any]
        XCTAssertEqual(size?["width"] as? Int,30)

        let audio = try files.temp("sound.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate:16000,channels:1))
        do {
            let writer = try AVAudioFile(forWriting:audio,settings:format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1600))
            buffer.frameLength = 1600
            for i in 0..<1600 { buffer.floatChannelData?[0][i] = Float(sin(Double(i) / 20) / 5) }
            try writer.write(from:buffer)
        }
        try files.store(audio,at:"data/sound.caf")
        let audioInfo = try await data("audio.info",["path":"data/sound.caf"]) as? [String:Any]
        XCTAssertEqual(audioInfo?["sampleRate"] as? Double,16000)

        let movie = try files.temp("fixture.mp4")
        let writer = try AVAssetWriter(outputURL:movie,fileType:.mp4)
        let video = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:160,AVVideoHeightKey:96])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:video,sourcePixelBufferAttributes:[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String:160,kCVPixelBufferHeightKey as String:96])
        writer.add(video)
        XCTAssertTrue(writer.startWriting(), writer.error?.localizedDescription ?? "")
        writer.startSession(atSourceTime:.zero)
        for frame in 0..<3 {
            let deadline = ContinuousClock.now + .seconds(10)
            while !video.isReadyForMoreMediaData {
                guard ContinuousClock.now < deadline else { throw RuntimeIssue("生成测试视频超时") }
                try await Task.sleep(for:.milliseconds(20))
            }
            var raw: CVPixelBuffer?
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil,pool,&raw),kCVReturnSuccess)
            let buffer = try XCTUnwrap(raw)
            CVPixelBufferLockBaseAddress(buffer,[])
            if let address = CVPixelBufferGetBaseAddress(buffer) { memset(address,Int32(frame * 40),CVPixelBufferGetBytesPerRow(buffer)*CVPixelBufferGetHeight(buffer)) }
            CVPixelBufferUnlockBaseAddress(buffer,[])
            XCTAssertTrue(adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:3)))
        }
        video.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RuntimeIssue("测试视频写入失败") }
        try files.store(movie,at:"data/clip.mp4")
        let videoInfo = try await data("video.info",["path":"data/clip.mp4"]) as? [String:Any]
        XCTAssertEqual(videoInfo?["width"] as? CGFloat,160)
        _ = try await data("video.thumbnail",["path":"data/clip.mp4","to":"data/still.jpg"])
        _ = try await data("video.transcode",["path":"data/clip.mp4","to":"data/export.mp4","quality":"passthrough"])
        let exported = try await data("video.info",["path":"data/export.mp4"]) as? [String:Any]
        XCTAssertEqual(exported?["height"] as? CGFloat,96)

        _ = try await data("notifications.setCategories",["categories":[["id":"notes","actions":[["id":"open","title":"打开"]]]]])
        let names = try await data("notifications.categories") as? [String]
        XCTAssertEqual(names,["notes"])
        _ = try await data("notifications.setCategories",["categories":[]])
    }

    func testPersonalStoresPhotoAndLocationOnDisposableSimulator() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("void-sdk-fixtures")
        try XCTSkipUnless(FileManager.default.fileExists(atPath:fixture.path), "此用例使用 CI 临时模拟器中的测试通讯录和日历")
        let grants = ["contacts.read","contacts.write","calendar.read","calendar.write","reminders","photos.read","photos.write","location.whenInUse"]
        sdk.declared.formUnion(grants)
        for key in grants { SDKConsent.shared.set(true,for:key,project:record.id) }
        defer { for key in grants { SDKConsent.shared.set(nil,for:key,project:record.id) } }
        for (method, expected) in [("contacts.authorization","authorized"), ("calendar.authorization","fullAccess"), ("reminders.authorization","fullAccess")] {
            let status = try await data(method) as? String
            guard status == expected else { throw RuntimeIssue(method + " 需要测试模拟器授权，实际为 " + (status ?? "未知")) }
        }
        let photoAccess = try await data("photos.authorization") as? [String:String]
        guard photoAccess?["readWrite"] == "authorized", photoAccess?["addOnly"] == "authorized" else { throw RuntimeIssue("测试模拟器需要相册读写授权") }
        let locationAccess = try await data("location.authorization") as? [String:String]
        guard ["whenInUse", "always"].contains(locationAccess?["status"] ?? "") else { throw RuntimeIssue("测试模拟器需要前台定位授权") }
        let label = "Void-" + UUID().uuidString
        let contactValue = try await data("contacts.create",["givenName":label,"phones":["5550100"]])
        let contact = try XCTUnwrap(contactValue as? String)
        _ = try await data("contacts.update",["id":contact,"organization":"void"])
        let details = try await data("contacts.get",["id":contact]) as? [String:Any]
        XCTAssertEqual(details?["organization"] as? String,"void")
        let found = try await data("contacts.search",["name":label]) as? [[String:Any]]
        XCTAssertEqual(found?.first?["id"] as? String,contact)
        _ = try await data("contacts.remove",["id":contact])

        let start = Date().addingTimeInterval(3600), end = start.addingTimeInterval(1800)
        let eventValue = try await data("calendar.createEvent",["title":label,"startDate":start.ISO8601Format(),"endDate":end.ISO8601Format()])
        let event = try XCTUnwrap(eventValue as? String)
        _ = try await data("calendar.updateEvent",["id":event,"title":label + "-updated"])
        let rows = try await data("calendar.events",["startDate":start.addingTimeInterval(-60).ISO8601Format(),"endDate":end.ISO8601Format()]) as? [[String:Any]]
        XCTAssertTrue(rows?.contains(where:{$0["title"] as? String == label + "-updated"}) == true)
        _ = try await data("calendar.deleteEvent",["id":event])

        let listValue = try await data("reminders.createList",["title":label]) as? [String:Any]
        let listID = try XCTUnwrap(listValue?["id"] as? String)
        let reminderValue = try await data("reminders.create",["title":label,"listId":listID,"dueDate":end.ISO8601Format()])
        let reminder = try XCTUnwrap(reminderValue as? String)
        _ = try await data("reminders.update",["id":reminder,"completed":true])
        let reminders = try await data("reminders.list",["listIds":[listID]]) as? [[String:Any]]
        XCTAssertEqual(reminders?.first?["completed"] as? Bool,true)
        _ = try await data("reminders.remove",["id":reminder])
        _ = try await data("reminders.deleteList",["id":listID])

        let image = UIGraphicsImageRenderer(size:CGSize(width:32,height:32)).image { c in UIColor.red.setFill(); c.fill(CGRect(x:0,y:0,width:32,height:32)) }
        let file = try sdk.files.temp("photo.jpg")
        try XCTUnwrap(image.jpegData(compressionQuality:0.9)).write(to:file)
        try sdk.files.store(file,at:"data/photo.jpg")
        let idValue = try await data("photos.save",["path":"data/photo.jpg","type":"image"])
        let asset = try XCTUnwrap(idValue as? String)
        let info = try await data("photos.asset",["id":asset]) as? [String:Any]
        XCTAssertEqual(info?["type"] as? String,"image")
        _ = try await data("photos.thumbnail",["id":asset,"to":"data/thumb.jpg"])
        let point = try await data("location.current") as? [String:Any]
        XCTAssertEqual(try XCTUnwrap(point?["latitude"] as? Double),37.3349,accuracy:0.005)
    }
}

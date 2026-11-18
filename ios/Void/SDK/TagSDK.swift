import CoreNFC
import Foundation

@MainActor
final class TagSDK: NSObject, SDKModule, NFCNDEFReaderSessionDelegate {
    private var reader: NFCNDEFReaderSession?
    private var result: SDKWait<Any>?
    private var writing: NFCNDEFMessage?
    private weak var events: SDKEvents?

    private func records(_ message: NFCNDEFMessage) -> [[String:Any]] {
        message.records.map { item in
            var value: [String:Any] = ["format":item.typeNameFormat.rawValue,"type":item.type.base64EncodedString(),
                                     "identifier":item.identifier.base64EncodedString(),"payload":item.payload.base64EncodedString()]
            let (text, _) = item.wellKnownTypeTextPayload()
            if let text { value["text"] = text }
            if let url = item.wellKnownTypeURIPayload() { value["url"] = url.absoluteString }
            return value
        }
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if method == "available" { return NFCNDEFReaderSession.readingAvailable }
        guard NFCNDEFReaderSession.readingAvailable else { throw SDKFailure.unavailable("需要支持 NFC 的 iPhone 及含标签读取能力的签名") }
        guard reader == nil else { throw SDKFailure("BUSY","已有 NFC 会话") }
        if method == "write" {
            guard let entries = a.values["records"] as? [[String:Any]], !entries.isEmpty else { throw SDKFailure.invalid("records") }
            writing = NFCNDEFMessage(records:try entries.map { entry in
                let p = SDKArgs(entry)
                if let text = entry["text"] as? String, let record = NFCNDEFPayload.wellKnownTypeTextPayload(string:text,locale:.current) { return record }
                if let url = entry["url"] as? String, let record = NFCNDEFPayload.wellKnownTypeURIPayload(string:url) { return record }
                guard let format = NFCTypeNameFormat(rawValue:UInt8(try p.int("format",range:0...6))) else { throw SDKFailure.invalid("format") }
                return NFCNDEFPayload(format:format,type:try p.data("type"),identifier:entry["identifier"] == nil ? Data() : try p.data("identifier"),payload:try p.data("payload"))
            })
        } else { writing = nil }
        let wait = SDKWait<Any>()
        events = s.events
        let reader = NFCNDEFReaderSession(delegate:self,queue:.main,invalidateAfterFirstRead:false)
        self.reader = reader; result = wait
        reader.alertMessage = try a.string("message","请将 iPhone 靠近 NFC 标签")
        reader.begin()
        defer { reader.invalidate(); result = nil; self.reader = nil; writing = nil }
        return try await wait.value()
    }
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) { events?.deliver?("nfc","nfc.state","active") }
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        guard session === reader else { return }
        let e = error as NSError
        let value = e.code == NFCReaderError.Code.readerSessionInvalidationErrorUserCanceled.rawValue ? SDKFailure("CANCELLED","已取消 NFC 会话") : SDKFailure("NFC_ERROR",e.localizedDescription)
        result?.finish(.failure(value)); events?.deliver?("nfc","nfc.state","ended")
    }
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        if session === reader, writing == nil, let message = messages.first { result?.finish(.success(["records":records(message)])) }
    }
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard session === reader, let tag = tags.first else { return }
        if tags.count != 1 { session.alertMessage = "请只靠近一个标签"; session.restartPolling(); return }
        Task { @MainActor in
            do {
                try await session.connect(to:tag)
                let (status, capacity) = try await tag.queryNDEFStatus()
                guard session === reader, let result else { return }
                if let writing {
                    guard status == .readWrite, writing.length <= capacity else { throw SDKFailure.unavailable("标签只读或容量不足") }
                    try await tag.writeNDEF(writing)
                    result.finish(.success(["bytes":writing.length,"capacity":capacity]))
                } else {
                    guard status != .notSupported else { throw SDKFailure.unavailable("该标签不支持 NDEF") }
                    let message = try await tag.readNDEF()
                    result.finish(.success(["records":records(message),"capacity":capacity,"writable":status == .readWrite] as [String:Any]))
                }
            } catch { if session === reader { result?.finish(.failure(error)) } }
        }
    }
    func close() { reader?.invalidate(); result?.finish(.failure(CancellationError())); result = nil; reader = nil }
}

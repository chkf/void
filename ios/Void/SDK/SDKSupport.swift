import Foundation
import UIKit

struct SDKFailure: LocalizedError {
    let code: String
    let detail: String
    init(_ code: String, _ detail: String) { self.code = code; self.detail = detail }
    var errorDescription: String? { detail }

    static func describe(_ error: Error) -> Self {
        if let sdk = error as? Self { return sdk }
        if error is CancellationError { return Self("CANCELLED", "操作已取消") }
        let e = error as NSError
        if e.domain == NSURLErrorDomain {
            if e.code == NSURLErrorCancelled { return Self("CANCELLED", "请求已取消") }
            if e.code == NSURLErrorTimedOut { return Self("TIMEOUT", "网络请求超时") }
            return Self("NETWORK_ERROR", e.localizedDescription)
        }
        if e.domain == NSCocoaErrorDomain {
            switch e.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return Self("NOT_FOUND", "文件不存在")
            case NSFileWriteFileExistsError: return Self("ALREADY_EXISTS", "目标已存在")
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return Self("PERMISSION_DENIED", "无法访问该文件")
            case NSUserCancelledError: return Self("CANCELLED", "用户已取消")
            default: break
            }
        }
        if error is FolderAccessIssue { return Self("PERMISSION_DENIED", e.localizedDescription) }
        return Self("NATIVE_ERROR", e.localizedDescription)
    }

    static func invalid(_ field: String) -> Self { Self("INVALID_PARAMS", "请检查参数 " + field) }
    static func unavailable(_ why: String) -> Self { Self("UNAVAILABLE", why) }
    static func denied(_ why: String) -> Self { Self("PERMISSION_DENIED", why) }
}

struct SDKArgs {
    let values: [String: Any]
    init(_ values: [String: Any]) { self.values = values }

    func string(_ key: String, _ fallback: String? = nil) throws -> String {
        if values[key] == nil, let fallback { return fallback }
        guard let s = values[key] as? String else { throw SDKFailure.invalid(key) }
        return s
    }
    func number(_ key: String, _ fallback: Double? = nil) throws -> Double {
        if values[key] == nil, let fallback { return fallback }
        guard let n = values[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { throw SDKFailure.invalid(key) }
        return n.doubleValue
    }
    func int(_ key: String, _ fallback: Int? = nil, range: ClosedRange<Int> = 0...Int.max) throws -> Int {
        if values[key] == nil, let fallback { return fallback }
        let n = try number(key)
        guard let i = Int(exactly: n), range.contains(i) else { throw SDKFailure.invalid(key) }
        return i
    }
    func bool(_ key: String, _ fallback: Bool = false) throws -> Bool {
        guard let value = values[key] else { return fallback }
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw SDKFailure.invalid(key) }
        return n.boolValue
    }
    func strings(_ key: String, _ fallback: [String] = []) throws -> [String] {
        guard let value = values[key] else { return fallback }
        guard let list = value as? [String] else { throw SDKFailure.invalid(key) }
        return list
    }
    func data(_ key: String) throws -> Data {
        guard let data = Data(base64Encoded: try string(key)) else { throw SDKFailure.invalid(key) }
        return data
    }
    func date(_ key: String) throws -> Date {
        let text = try string(key)
        let format = ISO8601DateFormatter()
        if let date = format.date(from: text) { return date }
        format.formatOptions.insert(.withFractionalSeconds)
        guard let date = format.date(from: text) else { throw SDKFailure.invalid(key) }
        return date
    }
    func choice(_ key: String, _ options: [String], _ fallback: String? = nil) throws -> String {
        let s = try string(key, fallback)
        guard options.contains(s) else { throw SDKFailure.invalid(key) }
        return s
    }
}

@MainActor
final class SDKWait<Value> {
    private var result: Result<Value, Error>?
    private var continuations: [UUID: CheckedContinuation<Value, Error>] = [:]

    func finish(_ value: Result<Value, Error>) {
        guard result == nil else { return }
        result = value
        let waiting = continuations.values
        continuations.removeAll()
        for continuation in waiting { continuation.resume(with: value) }
    }
    func value() async throws -> Value {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if let result { continuation.resume(with: result) }
                else { continuations[id] = continuation }
            }
        } onCancel: { Task { @MainActor in self.continuations.removeValue(forKey: id)?.resume(throwing: CancellationError()) } }
    }
}

@MainActor
final class SDKPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    weak var anchor: UIView?
    private weak var current: UIViewController?
    private var cancel: (() -> Void)?

    func show<T>(_ controller: UIViewController, until wait: SDKWait<T>) async throws -> T {
        guard cancel == nil else { throw SDKFailure("BUSY", "请先完成当前系统面板") }
        let scene = anchor?.window?.windowScene ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        guard let scene, scene.activationState == .foregroundActive,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { throw SDKFailure.unavailable("请在前台打开项目") }
        while let next = top.presentedViewController { top = next }
        guard !top.isBeingDismissed, !(top is UIAlertController) else { throw SDKFailure("BUSY", "请关闭当前提示后重试") }
        current = controller
        cancel = { wait.finish(.failure(CancellationError())) }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        controller.presentationController?.delegate = self
        top.present(controller, animated: true)
        controller.presentationController?.delegate = self
        defer {
            if current === controller {
                if controller.presentingViewController != nil { controller.dismiss(animated: false) }
                current = nil
                cancel = nil
            }
        }
        return try await wait.value()
    }

    func confirm(title: String, detail: String) async throws -> Bool {
        let wait = SDKWait<Bool>()
        let alert = UIAlertController(title: title, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "不允许", style: .cancel) { _ in wait.finish(.success(false)) })
        alert.addAction(UIAlertAction(title: "允许", style: .default) { _ in wait.finish(.success(true)) })
        return try await show(alert, until: wait)
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { cancel?() }
    func close() { cancel?(); current?.dismiss(animated: false); current = nil; cancel = nil }
}

@MainActor
final class SDKEvents {
    var deliver: ((String, String, Any) -> Void)?
    private var releases: [String: () -> Void] = [:]

    func add(_ id: String = UUID().uuidString, stop: @escaping () -> Void) -> String {
        releases[id]?()
        releases[id] = stop
        return id
    }
    func emit(_ id: String, _ name: String, _ value: Any) {
        if releases[id] != nil { deliver?(id, name, value) }
    }
    func stop(_ id: String) { releases.removeValue(forKey: id)?() }
    func close() {
        let actions = Array(releases.values)
        releases.removeAll()
        deliver = nil
        for release in actions { release() }
    }
}

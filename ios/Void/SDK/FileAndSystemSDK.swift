import UIKit
import UniformTypeIdentifiers
import QuickLook
import Network

@MainActor
final class DocumentChoice: NSObject, UIDocumentPickerDelegate {
    let result = SDKWait<[URL]>()
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { result.finish(.success(urls)) }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { result.finish(.failure(CancellationError())) }
}

@MainActor
final class FileSDK: SDKModule {
    static func share(_ items: [Any], in s: SDKSession) async throws -> Bool {
        let ui = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let wait = SDKWait<Bool>()
        ui.completionWithItemsHandler = { _, completed, _, error in
            if let error { wait.finish(.failure(error)) } else { wait.finish(.success(completed)) }
        }
        return try await s.ui.show(ui, until: wait)
    }

    static func transfer(_ method: String, _ a: SDKArgs, _ s: SDKSession, types: [UTType] = [.item]) async throws -> Any {
        let chooser = DocumentChoice()
        if method == "exportFile" {
            let input = try s.files.input(a.string("path"))
            let picker = UIDocumentPickerViewController(forExporting: [input], asCopy: true)
            picker.delegate = chooser
            _ = try await s.ui.show(picker, until: chooser.result)
            return NSNull()
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = try a.bool("multiple")
        picker.delegate = chooser
        let selected = try await s.ui.show(picker, until: chooser.result)
        var paths: [String] = []
        let dir = try a.string("directory", "data/Imports")
        for url in selected {
            let name = url.lastPathComponent
            guard ProjectFiles.component(name) else { throw SDKFailure.invalid("name") }
            let path = dir + "/" + UUID().uuidString + "/" + name
            try s.files.store(url, at: path)
            paths.append(path)
        }
        return paths
    }

    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        switch method {
        case "pick", "exportFile", "importFile":
            let types = try a.strings("types", [UTType.item.identifier]).compactMap(UTType.init)
            guard !types.isEmpty else { throw SDKFailure.invalid("types") }
            return try await Self.transfer(method, a, s, types: types)
        case "share": return try await Self.share([s.files.input(a.string("path"))], in: s)
        case "watch":
            let path = try a.string("path")
            let id = UUID().uuidString
            var previous = try s.files.signature(path)
            let task = Task { @MainActor [weak s] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                    guard let s, s.valid else { break }
                    do {
                        let value = try s.files.signature(path)
                        if value != previous { previous = value; s.events.emit(id, "files.changed", ["path":path]) }
                    } catch { s.events.emit(id, "error", ["message":error.localizedDescription]); break }
                }
            }
            return s.events.add(id) { task.cancel() }
        default:
            let files = s.files
            return try await Task.detached { try files.call(method, a) }.value
        }
    }
}

@MainActor
private final class DocumentPreview: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    let url: NSURL
    let result = SDKWait<Bool>()
    init(_ url: URL) { self.url = url as NSURL }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url }
    func previewControllerDidDismiss(_ controller: QLPreviewController) { result.finish(.success(true)) }
}

@MainActor
final class SystemSDK: SDKModule {
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        let device = UIDevice.current
        let scene = s.ui.anchor?.window?.windowScene ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch method {
        case "info": return ["name":device.systemName, "version":device.systemVersion, "model":device.model]
        case "appearance": return scene?.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
        case "battery":
            device.isBatteryMonitoringEnabled = true
            return ["level":device.batteryLevel, "state": ["unknown","unplugged","charging","full"][device.batteryState.rawValue]]
        case "readClipboard": return UIPasteboard.general.string as Any? ?? NSNull()
        case "writeClipboard": UIPasteboard.general.string = try a.string("text")
        case "share": return try await FileSDK.share([a.string("text")], in: s)
        case "preview":
            let delegate = DocumentPreview(try s.files.input(a.string("path")))
            guard QLPreviewController.canPreview(delegate.url) else { throw SDKFailure.unavailable("此文件无法预览") }
            let controller = QLPreviewController()
            controller.dataSource = delegate
            controller.delegate = delegate
            _ = try await s.ui.show(controller, until: delegate.result)
        case "openURL", "openSettings":
            let raw = method == "openSettings" ? UIApplication.openSettingsURLString : try a.string("url")
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), !["file","data","javascript","prefs","app-prefs"].contains(scheme) else { throw SDKFailure.invalid("url") }
            let options: [UIApplication.OpenExternalURLOptionsKey: Any] = try a.bool("universalOnly") ? [.universalLinksOnly:true] : [:]
            return await UIApplication.shared.open(url, options: options)
        case "haptic":
            let style = try a.choice("style", ["light","medium","heavy","success","warning","error"], "medium")
            if ["success","warning","error"].contains(style) {
                UINotificationFeedbackGenerator().notificationOccurred(style == "success" ? .success : (style == "warning" ? .warning : .error))
            } else { UIImpactFeedbackGenerator(style: style == "light" ? .light : (style == "heavy" ? .heavy : .medium)).impactOccurred() }
        case "brightness", "setBrightness":
            guard let screen = scene?.screen else { throw SDKFailure.unavailable("屏幕不可用") }
            if method == "setBrightness" {
                let value = try a.number("value")
                guard (0...1).contains(value) else { throw SDKFailure.invalid("value") }
                screen.brightness = CGFloat(value)
            }
            return Double(screen.brightness)
        case "orientation":
            guard let scene else { throw SDKFailure.unavailable("窗口不可用") }
            let value = try a.choice("value", ["portrait","landscapeLeft","landscapeRight","automatic"])
            let orientations: UIInterfaceOrientationMask = ["portrait":.portrait,"landscapeLeft":.landscapeLeft,"landscapeRight":.landscapeRight][value] ?? .allButUpsideDown
            let wait = SDKWait<Bool>()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in wait.finish(.failure(error)) }
            let observation = Task { @MainActor in
                for _ in 0..<40 {
                    let current = UIInterfaceOrientationMask(rawValue: 1 << scene.interfaceOrientation.rawValue)
                    if !orientations.intersection(current).isEmpty { wait.finish(.success(true)); return }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
                wait.finish(.failure(SDKFailure.unavailable("当前窗口未切换到指定方向")))
            }
            defer { observation.cancel() }
            _ = try await wait.value()
        default: throw SDKFailure("UNKNOWN_METHOD", method)
        }
        return NSNull()
    }
}

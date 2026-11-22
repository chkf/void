import Foundation
import UIKit

@MainActor
protocol SDKModule: AnyObject {
    func call(_ method: String, _ args: SDKArgs, in session: SDKSession) async throws -> Any
    func close()
}
extension SDKModule { func close() {} }

@MainActor
final class SDKConsent {
    static let shared = SDKConsent()
    private let defaults = UserDefaults.standard
    private func key(_ id: UUID) -> String { "void.permissions." + id.uuidString }

    func decision(_ name: String, project: UUID) -> Bool? {
        (defaults.dictionary(forKey: key(project))?[name] as? NSNumber)?.boolValue
    }
    func set(_ value: Bool?, for name: String, project: UUID) {
        var saved = defaults.dictionary(forKey: key(project)) ?? [:]
        saved[name] = value
        defaults.set(saved, forKey: key(project))
    }
    func history(_ id: UUID) -> [[String:String]] {
        defaults.array(forKey:key(id) + ".activity") as? [[String:String]] ?? []
    }
    func note(_ method: String, result: String, project: UUID) {
        var rows = history(project)
        if let latest = rows.last, latest["method"] == method, latest["result"] == result,
           let date = latest["time"].flatMap({ try? Date.ISO8601FormatStyle().parse($0) }), Date().timeIntervalSince(date) < 60 { return }
        rows.append(["time":Date().ISO8601Format(),"method":method,"result":result])
        defaults.set(Array(rows.suffix(50)), forKey:key(project) + ".activity")
    }
    static let labels = [
        "files.read":"读取项目文件", "files.write":"更改项目文件", "files.pick":"通过文件选择器导入文件", "files.share":"导出或分享项目文件",
        "photos.pick":"选择照片或视频", "photos.read":"读取照片图库", "photos.write":"保存到照片图库", "camera":"使用相机",
        "audio.record":"录制声音", "audio.play":"播放和处理音频", "video":"播放和处理视频", "location.whenInUse":"使用前台位置和航向",
        "calendar.read":"读取日历", "calendar.write":"更改日历事件", "reminders":"读取和更改提醒事项",
        "contacts.read":"读取联系人", "contacts.write":"更改联系人", "notifications":"安排和接收通知",
        "bluetooth":"扫描和连接蓝牙配件", "nfc":"与 NFC 标签交互", "health.read":"读取所选健康数据", "health.write":"写入所选健康数据",
        "home.read":"查看家庭和配件状态", "home.write":"控制家庭配件和场景", "biometrics":"使用生物识别验证",
        "clipboard.read":"读取剪贴板", "clipboard.write":"写入剪贴板", "system.share":"预览和分享内容", "system.links":"打开系统链接",
        "system.display":"调整屏幕显示", "system.haptics":"使用触感反馈", "network":"访问项目声明的网络服务",
        "graphics":"处理项目图像", "database":"使用项目专属数据库"
    ]
}

@MainActor
final class SDKSession: ObservableObject {
    let record: ProjectRecord
    let storage: URL
    let files: SDKFiles
    let ui = SDKPresenter()
    let events = SDKEvents()
    let access: SDKConsent
    private let trace: DirectoryTrace?
    var declared: Set<String>
    var networkHosts: Set<String>
    @Published var preview: CALayer?
    @Published var canvasHeight: CGFloat = 0
    private var modules: [String: SDKModule] = [:]
    private var pending: [String: Task<Void, Never>] = [:]
    var hasPendingRequests: Bool { !pending.isEmpty }
    private var asking: Task<Void, Error>?
    private(set) var valid = true
    static let methods: [String: [String: String]] = {
        guard let bytes = try? Toolchain.read("sdk-api.json"),
              let value = try? JSONDecoder().decode([String: [String: String]].self, from: bytes) else { return [:] }
        return value
    }()

    init(record: ProjectRecord, storage: URL, permissions: [String], networkHosts: [String], trace: DirectoryTrace? = nil) {
        self.record = record
        self.storage = storage
        self.trace = trace
        self.files = SDKFiles(record: record, storage: storage)
        self.declared = Set(permissions)
        self.networkHosts = Set(networkHosts.map { $0.lowercased() })
        access = .shared
    }

    func require(_ key: String) async throws {
        guard valid else { throw CancellationError() }
        guard !key.isEmpty else { return }
        guard declared.contains(key) else { throw SDKFailure("NOT_DECLARED", "请在 app/manifest.json 的 permissions 中添加 " + key) }
        if let allowed = access.decision(key, project: record.id) {
            guard allowed else { throw SDKFailure.denied("已拒绝" + (SDKConsent.labels[key] ?? key)) }
            return
        }
        if let asking { _ = try? await asking.value; try Task.checkCancellation(); return try await require(key) }
        let task = Task { @MainActor in
            defer { asking = nil }
            let label = SDKConsent.labels[key] ?? key
            trace?.event("sdk.consent.begin",key)
            let answer: Bool
            do {
                answer = try await ui.confirm(title: HostLanguage.format("允许「%@」%@？", record.name, HostLanguage.text(label)),
                                              detail: HostLanguage.text("void 会为这个项目记住你的选择。"))
                try Task.checkCancellation()
                guard valid else { throw CancellationError() }
            } catch {
                trace?.event("sdk.consent.end",key + " " + SDKFailure.describe(error).code,error:error)
                throw error
            }
            access.set(answer, for: key, project: record.id)
            trace?.event("sdk.consent.end",key + (answer ? " 允许" : " 拒绝"))
            if !answer { throw SDKFailure.denied("已拒绝" + label) }
        }
        asking = task
        try await task.value
    }

    func start(id: String, method: String, params: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard pending[id] == nil else {
            reply(["id": id, "result": ["success": false, "error": ["code":"DUPLICATE_REQUEST", "message":"请求标识重复"]]], nil)
            return
        }
        pending[id] = Task { @MainActor in
            let result: [String: Any]
            do {
                try Task.checkCancellation()
                let value = try await call(method, SDKArgs(params))
                try Task.checkCancellation()
                guard valid else { throw CancellationError() }
                result = ["success":true, "data":value]
            } catch {
                let e = SDKFailure.describe(error)
                result = ["success":false, "error":["code":e.code, "message":e.detail]]
            }
            let parts = method.components(separatedBy:".")
            if parts.count == 2, let permission = Self.methods[parts[0]]?[parts[1]], !permission.isEmpty {
                access.note(method, result:(result["error"] as? [String:String])?["code"] ?? "OK", project:record.id)
            }
            pending[id] = nil
            reply(["id":id, "result":result], nil)
        }
    }
    func cancel(_ id: String) {
        pending[id]?.cancel()
        if pending.values.allSatisfy({ $0.isCancelled }) { asking?.cancel() }
    }

    private func call(_ method: String, _ args: SDKArgs) async throws -> Any {
        guard valid else { throw CancellationError() }
        if method == "sdk.stop" { events.stop(try args.string("id")); return NSNull() }
        let parts = method.components(separatedBy: ".")
        guard parts.count == 2, let scope = Self.methods[parts[0]]?[parts[1]] else { throw SDKFailure("UNKNOWN_METHOD", "未注册的方法 " + method) }
        try await require(scope)
        try Task.checkCancellation()
        guard valid else { throw CancellationError() }
        let group = parts[0]
        let module: SDKModule
        if let existing = modules[group] { module = existing } else {
            switch group {
            case "fs": module = FileSDK()
            case "photos": module = PhotoSDK()
            case "camera": module = CameraSDK()
            case "audio": module = AudioSDK()
            case "video": module = VideoSDK()
            case "location": module = LocationSDK()
            case "calendar", "reminders": module = EventSDK(reminders: group == "reminders")
            case "contacts": module = ContactsSDK()
            case "notifications": module = NotificationSDK()
            case "bluetooth": module = BluetoothSDK()
            case "nfc": module = TagSDK()
            case "health": module = HealthSDK()
            case "home": module = HomeSDK()
            case "security": module = SecuritySDK()
            case "system": module = SystemSDK()
            case "network": module = NetworkSDK()
            case "graphics": module = GraphicsSDK()
            default: throw SDKFailure("UNKNOWN_METHOD", group)
            }
            modules[group] = module
        }
        return try await module.call(parts[1], args, in: self)
    }

    func close() {
        guard valid else { return }
        valid = false
        asking?.cancel()
        for task in pending.values { task.cancel() }
        events.close()
        ui.close()
        for module in modules.values { module.close() }
        modules.removeAll()
        preview = nil
        canvasHeight = 0
    }
}

import UIKit
import UserNotifications

final class VoidAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let exitDiagnostics = HostExitDiagnostics()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        exitDiagnostics.subscribe()
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner,.sound,.list]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        guard let project = request.content.userInfo["project"] as? String, let uuid = UUID(uuidString:project),
              request.identifier.hasPrefix(uuid.uuidString + "/") else { return }
        await MainActor.run {
            let key = "void.notifications." + uuid.uuidString
            var values = UserDefaults.standard.array(forKey:key) as? [[String:String]] ?? []
            let event = ["id":String(request.identifier.dropFirst(37)),"action":response.actionIdentifier, "date":Date().ISO8601Format()]
            values.append(event)
            UserDefaults.standard.set(Array(values.suffix(200)),forKey:key)
            NotificationCenter.default.post(name:.init("void.notification.response"), object:uuid, userInfo:event)
        }
    }
}

@MainActor
final class NotificationSDK: SDKModule {
    private let center = UNUserNotificationCenter.current()
    private var observer: NSObjectProtocol?
    private func state(_ status: UNAuthorizationStatus) -> String {
        switch status { case .authorized:return "authorized"; case .provisional:return "provisional"; case .ephemeral:return "ephemeral"; case .notDetermined:return "notDetermined"; case .denied:return "denied"; @unknown default:return "unknown" }
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        let project = s.record.id, prefix = project.uuidString + "/"
        if method == "authorization" { return await state(center.notificationSettings().authorizationStatus) }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName:.init("void.notification.response"), object:nil, queue:.main) { [weak s] note in
                guard (note.object as? UUID) == project else { return }
                let value = note.userInfo as? [String:String] ?? [:]
                Task { @MainActor in s?.events.deliver?("notifications","notifications.response",value) }
            }
        }
        if method == "responses" {
            let key = "void.notifications." + project.uuidString
            let saved = UserDefaults.standard.array(forKey:key) ?? []
            if try a.bool("consume", true) { UserDefaults.standard.removeObject(forKey:key) }
            return saved
        }
        if method == "request" { return try await center.requestAuthorization(options:[.alert,.badge,.sound]) }
        switch method {
        case "pending":
            return await center.pendingNotificationRequests().filter{$0.identifier.hasPrefix(prefix)}.map { req -> [String:Any] in
                var value: [String:Any] = ["id":String(req.identifier.dropFirst(prefix.count)),"title":req.content.title,"body":req.content.body,"repeats":req.trigger?.repeats ?? false]
                if let t = req.trigger as? UNCalendarNotificationTrigger { value["nextDate"] = t.nextTriggerDate()?.ISO8601Format() }
                if let t = req.trigger as? UNTimeIntervalNotificationTrigger { value["nextDate"] = t.nextTriggerDate()?.ISO8601Format() }
                return value
            }
        case "categories","setCategories":
            let old = await center.notificationCategories()
            if method == "categories" { return old.map(\.identifier).filter{$0.hasPrefix(prefix)}.map{String($0.dropFirst(prefix.count))}.sorted() }
            guard let entries = a.values["categories"] as? [[String:Any]] else { throw SDKFailure.invalid("categories") }
            var next = Set(old.filter{!$0.identifier.hasPrefix(prefix)})
            for entry in entries {
                let arg = SDKArgs(entry), id = try arg.string("id")
                let actions = try (entry["actions"] as? [[String:Any]] ?? []).map { params in
                    UNNotificationAction(identifier:try SDKArgs(params).string("id"), title:try SDKArgs(params).string("title"), options:[.foreground])
                }
                next.insert(UNNotificationCategory(identifier:prefix+id, actions:actions, intentIdentifiers:[],options:[]))
            }
            center.setNotificationCategories(next)
        case "cancel":
            let id = prefix + (try a.string("id"))
            center.removePendingNotificationRequests(withIdentifiers:[id]); center.removeDeliveredNotifications(withIdentifiers:[id])
        case "schedule":
            let auth = await center.notificationSettings().authorizationStatus
            if auth == .notDetermined { guard try await center.requestAuthorization(options:[.alert,.sound,.badge]) else { throw SDKFailure.denied("通知未获授权") } }
            else if auth == .denied { throw SDKFailure.denied("通知未获授权") }
            let id = try a.string("id",UUID().uuidString)
            let content = UNMutableNotificationContent()
            content.title = try a.string("title")
            content.body = try a.string("body","")
            if try a.bool("sound",true) { content.sound = .default }
            content.userInfo = ["project":project.uuidString]
            if a.values["category"] != nil { content.categoryIdentifier = prefix + (try a.string("category")) }
            let repeats = try a.bool("repeats")
            let trigger: UNNotificationTrigger?
            if a.values["at"] != nil {
                let date = try a.date("at"), calendar = Calendar.current
                guard date > Date() || repeats else { throw SDKFailure.invalid("at") }
                let units: Set<Calendar.Component> = repeats ? [.hour,.minute,.second] : [.year,.month,.day,.hour,.minute,.second]
                trigger = UNCalendarNotificationTrigger(dateMatching:calendar.dateComponents(units,from:date),repeats:repeats)
            } else if a.values["afterSeconds"] != nil {
                let seconds = try a.number("afterSeconds")
                guard seconds > 0, !repeats || seconds >= 60 else { throw SDKFailure.invalid("afterSeconds") }
                trigger = UNTimeIntervalNotificationTrigger(timeInterval:seconds,repeats:repeats)
            } else { guard !repeats else { throw SDKFailure.invalid("afterSeconds") }; trigger = nil }
            try await center.add(UNNotificationRequest(identifier:prefix+id,content:content,trigger:trigger))
            return id
        default: throw SDKFailure("UNKNOWN_METHOD", method)
        }
        return NSNull()
    }
    func close() { if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil }
}

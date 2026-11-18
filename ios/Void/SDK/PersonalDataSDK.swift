import Contacts
import EventKit
import Foundation

@MainActor
final class EventSDK: SDKModule {
    private let store = EKEventStore()
    private let reminders: Bool
    init(reminders: Bool) { self.reminders = reminders }
    private var entity: EKEntityType { reminders ? .reminder : .event }
    private func access(writeOnly: Bool = false) async throws {
        let status = EKEventStore.authorizationStatus(for: entity)
        if status == .fullAccess || (writeOnly && status == .writeOnly) { return }
        guard status != .restricted && status != .denied else { throw SDKFailure.denied("请在系统设置中允许访问") }
        let ok: Bool
        if reminders { ok = try await store.requestFullAccessToReminders() }
        else if writeOnly { ok = try await store.requestWriteOnlyAccessToEvents() }
        else { ok = try await store.requestFullAccessToEvents() }
        guard ok else { throw SDKFailure.denied("系统未授予所需访问权限") }
    }
    private func calendar(_ id: String) throws -> EKCalendar {
        guard let c = store.calendar(withIdentifier:id), store.calendars(for:entity).contains(where:{$0.calendarIdentifier == id}) else { throw SDKFailure("NOT_FOUND","列表不存在或不可见") }
        return c
    }
    private func describe(_ c: EKCalendar) -> [String:Any] { ["id":c.calendarIdentifier,"title":c.title,"writable":c.allowsContentModifications] }
    private func event(_ e: EKEvent) -> [String:Any] {
        ["id":e.eventIdentifier ?? e.calendarItemIdentifier,"title":e.title ?? "", "calendarId":e.calendar.calendarIdentifier,
         "startDate":e.startDate.ISO8601Format(),"endDate":e.endDate.ISO8601Format(),"allDay":e.isAllDay,"notes":e.notes ?? "","location":e.location ?? ""]
    }
    private func reminder(_ r: EKReminder) -> [String:Any] {
        var value: [String:Any] = ["id":r.calendarItemIdentifier,"title":r.title ?? "","listId":r.calendar.calendarIdentifier,"completed":r.isCompleted,"notes":r.notes ?? ""]
        if let components = r.dueDateComponents, let date = Calendar.current.date(from:components) { value["dueDate"] = date.ISO8601Format() }
        return value
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if method == "authorization" {
            switch EKEventStore.authorizationStatus(for: entity) {
            case .notDetermined: return "notDetermined"
            case .denied: return "denied"
            case .restricted: return "restricted"
            case .writeOnly: return "writeOnly"
            case .fullAccess: return "fullAccess"
            default: return "unknown"
            }
        }
        if !reminders && ["updateEvent","deleteEvent"].contains(method) { try await s.require("calendar.read") }
        try await access(writeOnly: method == "createEvent")
        switch method {
        case "listCalendars","lists": return store.calendars(for:entity).map(describe)
        case "events":
            let start = try a.date("startDate"), end = try a.date("endDate")
            guard end > start, end.timeIntervalSince(start) <= 4 * 366 * 86400 else { throw SDKFailure.invalid("endDate") }
            let ids = try a.strings("calendarIds")
            let predicate = store.predicateForEvents(withStart:start, end:end, calendars:ids.isEmpty ? nil : try ids.map(calendar))
            return Array(store.events(matching:predicate).prefix(try a.int("limit", 500, range:1...2000))).map(event)
        case "createEvent","updateEvent","deleteEvent":
            let e: EKEvent
            if method == "createEvent" {
                e = EKEvent(eventStore:store)
                if a.values["calendarId"] != nil { e.calendar = try calendar(a.string("calendarId")) }
                else { e.calendar = store.defaultCalendarForNewEvents }
                guard e.calendar != nil else { throw SDKFailure.unavailable("设备没有可写日历") }
            } else {
                guard let existing = try store.event(withIdentifier:a.string("id")) else { throw SDKFailure("NOT_FOUND","事件不存在或不可见") }
                e = existing
            }
            if method == "deleteEvent" { try store.remove(e, span:.thisEvent); return NSNull() }
            if method == "updateEvent" && a.values["calendarId"] != nil { e.calendar = try calendar(a.string("calendarId")) }
            if method == "createEvent" || a.values["title"] != nil { e.title = try a.string("title") }
            if method == "createEvent" || a.values["startDate"] != nil { e.startDate = try a.date("startDate") }
            if method == "createEvent" || a.values["endDate"] != nil { e.endDate = try a.date("endDate") }
            guard e.endDate >= e.startDate else { throw SDKFailure.invalid("endDate") }
            if a.values["allDay"] != nil { e.isAllDay = try a.bool("allDay") }
            if a.values["notes"] != nil { e.notes = try a.string("notes") }
            if a.values["location"] != nil { e.location = try a.string("location") }
            try store.save(e, span:.thisEvent)
            return e.eventIdentifier ?? e.calendarItemIdentifier
        case "list":
            let ids = try a.strings("listIds"), max = try a.int("limit", 500, range:1...2000)
            let query = store.predicateForReminders(in:ids.isEmpty ? nil : try ids.map(calendar))
            let wait = SDKWait<[EKReminder]>()
            let token = store.fetchReminders(matching:query) { values in Task { @MainActor in wait.finish(.success(values ?? [])) } }
            defer { store.cancelFetchRequest(token) }
            return try await wait.value().prefix(max).map(reminder)
        case "create","update","remove":
            let r: EKReminder
            if method == "create" {
                r = EKReminder(eventStore:store)
                r.calendar = a.values["listId"] == nil ? store.defaultCalendarForNewReminders() : try calendar(a.string("listId"))
                guard r.calendar != nil else { throw SDKFailure.unavailable("设备没有提醒列表") }
            } else {
                guard let existing = try store.calendarItem(withIdentifier:a.string("id")) as? EKReminder else { throw SDKFailure("NOT_FOUND","提醒不存在或不可见") }
                r = existing
            }
            if method == "remove" { try store.remove(r, commit:true); return NSNull() }
            if method == "update" && a.values["listId"] != nil { r.calendar = try calendar(a.string("listId")) }
            if method == "create" || a.values["title"] != nil { r.title = try a.string("title") }
            if a.values["notes"] != nil { r.notes = try a.string("notes") }
            if a.values["completed"] != nil { r.isCompleted = try a.bool("completed") }
            if a.values["dueDate"] is NSNull { r.dueDateComponents = nil }
            else if a.values["dueDate"] != nil { r.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone], from:try a.date("dueDate")) }
            try store.save(r, commit:true)
            return r.calendarItemIdentifier
        case "createList","updateList","deleteList":
            let c: EKCalendar
            if method == "createList" {
                c = EKCalendar(for:.reminder, eventStore:store)
                guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where:{$0.sourceType == .local}) else { throw SDKFailure.unavailable("没有可写提醒来源") }
                c.source = source
            } else { c = try calendar(a.string("id")) }
            if method == "deleteList" { try store.removeCalendar(c, commit:true); return NSNull() }
            c.title = try a.string("title")
            try store.saveCalendar(c, commit:true)
            return describe(c)
        default: throw SDKFailure("UNKNOWN_METHOD", method)
        }
    }
}

@MainActor
final class ContactsSDK: SDKModule {
    private let store = CNContactStore()
    private let keys: [CNKeyDescriptor] = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
    private func describe(_ c: CNContact) -> [String:Any] {
        ["id":c.identifier,"givenName":c.givenName,"familyName":c.familyName,"organization":c.organizationName,
         "phones":c.phoneNumbers.map{$0.value.stringValue},"emails":c.emailAddresses.map{$0.value as String}]
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        let status = CNContactStore.authorizationStatus(for:.contacts)
        if method == "authorization" {
            if #available(iOS 18, *), status == .limited { return "limited" }
            switch status { case .authorized:return "authorized"; case .notDetermined:return "notDetermined"; case .denied:return "denied"; case .restricted:return "restricted"; default:return "unknown" }
        }
        if status == .notDetermined {
            guard try await store.requestAccess(for:.contacts) else { throw SDKFailure.denied("联系人访问未获授权") }
        } else if status == .denied || status == .restricted { throw SDKFailure.denied("联系人访问未获授权") }
        switch method {
        case "search":
            let filter = try a.string("name",""), count = try a.int("limit",100,range:1...1000)
            let request = CNContactFetchRequest(keysToFetch:keys)
            if !filter.isEmpty { request.predicate = CNContact.predicateForContacts(matchingName:filter) }
            var found: [[String:Any]] = []
            try store.enumerateContacts(with:request) { c, stop in found.append(self.describe(c)); if found.count == count { stop.pointee = true } }
            return found
        case "get": return try describe(store.unifiedContact(withIdentifier:a.string("id"),keysToFetch:keys))
        case "create","update","remove":
            let c: CNMutableContact
            if method == "create" { c = CNMutableContact() }
            else {
                guard let existing = try store.unifiedContact(withIdentifier:a.string("id"),keysToFetch:keys).mutableCopy() as? CNMutableContact else { throw SDKFailure("NOT_FOUND","联系人不存在") }
                c = existing
            }
            let save = CNSaveRequest()
            if method == "remove" { save.delete(c); try store.execute(save); return NSNull() }
            if a.values["givenName"] != nil { c.givenName = try a.string("givenName") }
            if a.values["familyName"] != nil { c.familyName = try a.string("familyName") }
            if a.values["organization"] != nil { c.organizationName = try a.string("organization") }
            if a.values["phones"] != nil { c.phoneNumbers = try a.strings("phones").map { CNLabeledValue(label:CNLabelPhoneNumberMain,value:CNPhoneNumber(stringValue:$0)) } }
            if a.values["emails"] != nil { c.emailAddresses = try a.strings("emails").map { CNLabeledValue(label:CNLabelHome,value:$0 as NSString) } }
            if method == "create" { save.add(c,toContainerWithIdentifier:nil) } else { save.update(c) }
            try store.execute(save)
            return c.identifier
        default: throw SDKFailure("UNKNOWN_METHOD", method)
        }
    }
}

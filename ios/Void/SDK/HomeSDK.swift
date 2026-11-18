import Foundation
import HomeKit

@MainActor
final class HomeSDK: NSObject, SDKModule, HMHomeManagerDelegate, HMAccessoryDelegate {
    private var manager: HMHomeManager?
    private let ready = SDKWait<Bool>()
    private weak var events: SDKEvents?
    private var watched: [UUID:String] = [:]

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        ready.finish(.success(true))
        events?.deliver?("home","home.changed",manager.homes.map{$0.uniqueIdentifier.uuidString})
    }
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        if status.contains(.restricted) || (status.contains(.determined) && !status.contains(.authorized)) { ready.finish(.failure(SDKFailure.denied("家庭访问未获授权"))) }
    }
    private func json(_ value: Any?) -> Any {
        switch value {
        case let data as Data: return ["base64":data.base64EncodedString()]
        case let number as NSNumber: return number
        case let s as String: return s
        default: return NSNull()
        }
    }
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        guard let id = watched[characteristic.uniqueIdentifier] else { return }
        events?.emit(id,"home.value",["characteristic":characteristic.uniqueIdentifier.uuidString,"value":json(characteristic.value)])
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        events = s.events
        if manager == nil { let m = HMHomeManager(); manager = m; m.delegate = self }
        guard let manager else { throw SDKFailure.unavailable("家庭服务不可用") }
        _ = try await ready.value()
        if manager.authorizationStatus.contains(.restricted) || !manager.authorizationStatus.contains(.authorized) { throw SDKFailure.denied("请在系统设置中允许访问家庭，并使用带 HomeKit 能力的签名") }
        if method == "homes" { return manager.homes.map{ ["id":$0.uniqueIdentifier.uuidString,"name":$0.name] } }
        let homeID = try a.string("home")
        guard let home = manager.homes.first(where:{ $0.uniqueIdentifier.uuidString == homeID }) else { throw SDKFailure("NOT_FOUND","家庭不可见") }
        if method == "scenes" { return home.actionSets.map{["id":$0.uniqueIdentifier.uuidString,"name":$0.name]} }
        if method == "runScene" {
            let id = try a.string("scene")
            guard let scene = home.actionSets.first(where:{$0.uniqueIdentifier.uuidString == id}) else { throw SDKFailure("NOT_FOUND","场景不存在") }
            try await home.executeActionSet(scene); return NSNull()
        }
        if method == "accessories" {
            return home.accessories.map { item -> [String:Any] in
                let services = item.services.map { service -> [String:Any] in
                    let chars = service.characteristics.map { c -> [String:Any] in
                        ["id":c.uniqueIdentifier.uuidString,"name":c.localizedDescription,"type":c.characteristicType,"properties":c.properties]
                    }
                    return ["name":service.name,"id":service.uniqueIdentifier.uuidString,"characteristics":chars]
                }
                return ["id":item.uniqueIdentifier.uuidString,"name":item.name,"reachable":item.isReachable,"services":services]
            }
        }
        let id = try a.string("characteristic")
        guard let c = home.accessories.flatMap(\.services).flatMap(\.characteristics).first(where:{$0.uniqueIdentifier.uuidString == id}) else { throw SDKFailure("NOT_FOUND","特征不存在") }
        switch method {
        case "read":
            guard c.properties.contains(HMCharacteristicPropertyReadable) else { throw SDKFailure.unavailable("特征不可读") }
            try await c.readValue(); return json(c.value)
        case "write":
            guard c.properties.contains(HMCharacteristicPropertyWritable) else { throw SDKFailure.unavailable("特征不可写") }
            guard let value = a.values["value"] else { throw SDKFailure.invalid("value") }
            if let number = value as? NSNumber { try await c.writeValue(number) }
            else if let text = value as? String { try await c.writeValue(text) }
            else if let bytes = value as? [String:Any] { try await c.writeValue(SDKArgs(bytes).data("base64")) }
            else { throw SDKFailure.invalid("value") }
        case "subscribe":
            guard c.properties.contains(HMCharacteristicPropertySupportsEventNotification) else { throw SDKFailure.unavailable("特征不提供通知") }
            guard watched[c.uniqueIdentifier] == nil else { throw SDKFailure("BUSY","此特征已订阅") }
            c.service?.accessory?.delegate = self
            try await c.enableNotification(true)
            let sub = UUID().uuidString; watched[c.uniqueIdentifier] = sub
            return s.events.add(sub) { [weak self] in self?.watched[c.uniqueIdentifier] = nil; c.enableNotification(false) { _ in } }
        default: throw SDKFailure("UNKNOWN_METHOD",method)
        }
        return NSNull()
    }
    func close() { ready.finish(.failure(CancellationError())); manager?.delegate = nil; manager = nil; watched.removeAll() }
}

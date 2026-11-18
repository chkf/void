import CoreBluetooth
import Foundation

@MainActor
final class BluetoothSDK: NSObject, SDKModule, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager?
    private var powered = SDKWait<Bool>()
    private weak var events: SDKEvents?
    private var scanID: String?
    private var devices: [UUID:CBPeripheral] = [:]
    private var pending: [String:SDKWait<Any>] = [:]
    private var subscriptions: [String:String] = [:]

    private func power(_ state: CBManagerState) -> String {
        switch state { case .poweredOn:return "on"; case .poweredOff:return "off"; case .unsupported:return "unsupported"; case .unauthorized:return "denied"; case .resetting:return "resetting"; default:return "unknown" }
    }
    private func check(_ central: CBCentralManager) async throws {
        if central.state == .unknown || central.state == .resetting { _ = try await powered.value() }
        guard central.state == .poweredOn else { throw SDKFailure.unavailable("蓝牙状态 " + power(central.state)) }
    }
    private func operation(_ key: String, _ start: () -> Void) async throws -> Any {
        guard pending[key] == nil else { throw SDKFailure("BUSY","同一蓝牙操作正在进行") }
        let wait = SDKWait<Any>(); pending[key] = wait
        start()
        defer { if pending[key] === wait { pending[key] = nil } }
        return try await wait.value()
    }
    private func finish(_ key: String, _ value: Any, _ error: Error?) {
        pending.removeValue(forKey:key)?.finish(error.map(Result.failure) ?? .success(value))
    }
    private func outcome(_ p: CBPeripheral, _ c: CBCharacteristic) -> String {
        p.identifier.uuidString + "/" + (c.service?.uuid.uuidString ?? "") + "/" + c.uuid.uuidString
    }
    private func disconnected(_ peripheral: CBPeripheral, _ error: Error?) {
        let p = peripheral.identifier.uuidString
        finish(p + "/disconnect", NSNull(), error)
        let e = error ?? SDKFailure("DISCONNECTED","蓝牙设备已断开")
        for key in Array(pending.keys) where key.hasPrefix(p + "/") { finish(key, NSNull(), e) }
        for (key,id) in Array(subscriptions) where key.hasPrefix(p + "/") {
            events?.emit(id,"bluetooth.disconnected",["peripheral":p]); events?.stop(id)
        }
        events?.deliver?("bluetooth","bluetooth.connection",["peripheral":p,"state":"disconnected"])
    }

    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if method == "authorization" {
            switch CBManager.authorization { case .allowedAlways:return "authorized"; case .restricted:return "restricted"; case .denied:return "denied"; default:return "notDetermined" }
        }
        events = s.events
        if central == nil { central = CBCentralManager(delegate:self,queue:.main,options:[CBCentralManagerOptionShowPowerAlertKey:false]) }
        guard let central else { throw SDKFailure.unavailable("蓝牙不可用") }
        if method == "state" {
            if central.state == .unknown { _ = try await powered.value() }
            return power(central.state)
        }
        try await check(central)
        if method == "scan" {
            guard scanID == nil else { throw SDKFailure("BUSY","扫描已开始") }
            let filters = try a.strings("services").map { CBUUID(string:$0) }, id = UUID().uuidString
            scanID = id
            central.scanForPeripherals(withServices:filters.isEmpty ? nil : filters,options:[CBCentralManagerScanOptionAllowDuplicatesKey:false])
            return s.events.add(id) { [weak self] in self?.central?.stopScan(); self?.scanID = nil }
        }
        guard let uuid = UUID(uuidString:try a.string("peripheral")), let p = devices[uuid] else { throw SDKFailure("NOT_FOUND","请先扫描并选择蓝牙设备") }
        let key = uuid.uuidString
        if method == "connect" {
            if p.state == .connected { return key }
            do { return try await operation(key + "/connect") { central.connect(p) } }
            catch { if error is CancellationError { central.cancelPeripheralConnection(p) }; throw error }
        }
        guard p.state == .connected else { throw SDKFailure("DISCONNECTED","请先连接设备") }
        if method == "disconnect" { return try await operation(key + "/disconnect") { central.cancelPeripheralConnection(p) } }
        if method == "services" { return try await operation(key + "/services") { p.discoverServices(nil) } }
        let serviceUUID = try a.string("service")
        guard let service = p.services?.first(where:{ $0.uuid.uuidString.caseInsensitiveCompare(serviceUUID) == .orderedSame }) else { throw SDKFailure("NOT_FOUND","请先发现所需服务") }
        if method == "characteristics" { return try await operation(key + "/" + service.uuid.uuidString + "/chars") { p.discoverCharacteristics(nil,for:service) } }
        let charUUID = try a.string("characteristic")
        guard let c = service.characteristics?.first(where:{$0.uuid.uuidString.caseInsensitiveCompare(charUUID) == .orderedSame}) else { throw SDKFailure("NOT_FOUND","请先发现所需特征") }
        let ch = outcome(p,c)
        switch method {
        case "read":
            guard c.properties.contains(.read) else { throw SDKFailure.unavailable("该特征不可读") }
            return try await operation(ch + "/read") { p.readValue(for:c) }
        case "write":
            let reply = try a.bool("withResponse",true), type: CBCharacteristicWriteType = reply ? .withResponse : .withoutResponse
            guard c.properties.contains(reply ? .write : .writeWithoutResponse) else { throw SDKFailure.unavailable("该特征不支持所选写入方式") }
            let data = try a.data("data")
            guard data.count <= p.maximumWriteValueLength(for:type) else { throw SDKFailure("TOO_LARGE","数据超过此设备单次写入长度") }
            if reply { return try await operation(ch + "/write") { p.writeValue(data,for:c,type:type) } }
            guard p.canSendWriteWithoutResponse else { throw SDKFailure("BUSY","设备正在处理前一次写入") }
            p.writeValue(data,for:c,type:type)
            return NSNull()
        case "subscribe":
            guard c.properties.contains(.notify) || c.properties.contains(.indicate) else { throw SDKFailure.unavailable("该特征不支持通知") }
            guard subscriptions[ch] == nil else { throw SDKFailure("BUSY","该特征已订阅") }
            _ = try await operation(ch + "/notify") { p.setNotifyValue(true,for:c) }
            let id = UUID().uuidString
            subscriptions[ch] = id
            return s.events.add(id) { [weak self, weak p, weak c] in
                self?.subscriptions[ch] = nil
                if let p, let c, p.state == .connected { p.setNotifyValue(false,for:c) }
            }
        default: throw SDKFailure("UNKNOWN_METHOD",method)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state != .unknown && central.state != .resetting else { powered = SDKWait<Bool>(); return }
        powered.finish(.success(true))
        events?.deliver?("bluetooth","bluetooth.state",power(central.state))
        if central.state != .poweredOn {
            if let scanID { events?.stop(scanID) }
            for p in devices.values { disconnected(p, SDKFailure.unavailable("蓝牙不可用")) }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String:Any], rssi RSSI: NSNumber) {
        guard let scanID else { return }
        devices[p.identifier] = p; p.delegate = self
        events?.emit(scanID,"bluetooth.device",["id":p.identifier.uuidString,"name":p.name ?? "","rssi":RSSI,
            "services":(advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)] as [String:Any])
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        p.delegate = self; finish(p.identifier.uuidString + "/connect",p.identifier.uuidString,nil)
        events?.deliver?("bluetooth","bluetooth.connection",["peripheral":p.identifier.uuidString,"state":"connected"])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { disconnected(p,error ?? SDKFailure("CONNECTION_FAILED","连接失败")) }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { disconnected(p,error) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) { finish(p.identifier.uuidString + "/services",p.services?.map{$0.uuid.uuidString} ?? [],error) }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let items = (service.characteristics ?? []).map { c -> [String:Any] in
            ["id":c.uuid.uuidString,"read":c.properties.contains(.read),"write":c.properties.contains(.write),
             "writeWithoutResponse":c.properties.contains(.writeWithoutResponse),"notify":c.properties.contains(.notify) || c.properties.contains(.indicate)]
        }
        finish(p.identifier.uuidString + "/" + service.uuid.uuidString + "/chars",items,error)
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        let key = outcome(p,c), data = c.value?.base64EncodedString() ?? ""
        finish(key + "/read",data,error)
        if let sub = subscriptions[key] { events?.emit(sub,error == nil ? "bluetooth.value" : "error", error.map{$0.localizedDescription} ?? data) }
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) { finish(outcome(p,c) + "/write",NSNull(),error) }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) { finish(outcome(p,c) + "/notify",NSNull(),error) }
    func close() {
        powered.finish(.failure(CancellationError()))
        for waiter in pending.values { waiter.finish(.failure(CancellationError())) }; pending.removeAll()
        if let central, central.state == .poweredOn {
            central.stopScan()
            for p in devices.values where p.state != .disconnected { central.cancelPeripheralConnection(p) }
        }
        central?.delegate = nil; for p in devices.values { p.delegate = nil }; subscriptions.removeAll(); devices.removeAll()
    }
}

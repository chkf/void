import CoreLocation
import Foundation

@MainActor
final class LocationSDK: NSObject, SDKModule, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorization: SDKWait<Bool>?
    private var positions: [String:SDKWait<CLLocation>] = [:]
    private var watchers = Set<String>()
    private var headings = Set<String>()
    private weak var events: SDKEvents?

    override init() { super.init(); manager.delegate = self }
    private func state() -> String {
        switch manager.authorizationStatus {
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        case .denied: return "denied"
        case .restricted: return "restricted"
        default: return "notDetermined"
        }
    }
    private func authorize() async throws {
        guard CLLocationManager.locationServicesEnabled() else { throw SDKFailure.unavailable("系统定位服务未启用") }
        if manager.authorizationStatus == .notDetermined {
            let wait = authorization ?? SDKWait<Bool>()
            authorization = wait
            manager.requestWhenInUseAuthorization()
            _ = try await wait.value()
        }
        guard [.authorizedAlways,.authorizedWhenInUse].contains(manager.authorizationStatus) else { throw SDKFailure.denied("定位未获授权") }
    }
    private func location(_ point: CLLocation) -> [String:Any] {
        ["latitude":point.coordinate.latitude,"longitude":point.coordinate.longitude,"accuracy":point.horizontalAccuracy,"altitude":point.altitude,
         "speed":point.speed, "timestamp":point.timestamp.ISO8601Format()]
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        authorization?.finish(.success(true)); authorization = nil
        if [.denied,.restricted].contains(manager.authorizationStatus) { locationManager(manager,didFailWithError:SDKFailure.denied("定位授权已撤销")) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let point = locations.last else { return }
        for wait in positions.values { wait.finish(.success(point)) }
        for id in watchers { events?.emit(id,"location.position",location(point)) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading value: CLHeading) {
        for id in headings { events?.emit(id,"location.heading",["magnetic":value.magneticHeading,"true":value.trueHeading,"accuracy":value.headingAccuracy]) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        for wait in positions.values { wait.finish(.failure(error)) }
        for id in watchers.union(headings) { events?.emit(id,"error",["message":error.localizedDescription]) }
    }
    private func updateStreams() {
        if positions.isEmpty && watchers.isEmpty { manager.stopUpdatingLocation() } else { manager.startUpdatingLocation() }
        if headings.isEmpty { manager.stopUpdatingHeading() } else { manager.startUpdatingHeading() }
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if method == "authorization" { return ["status":state(),"accuracy":manager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced"] }
        if method == "geocode" || method == "reverseGeocode" {
            let geocoder = CLGeocoder()
            return try await withTaskCancellationHandler {
                let results: [CLPlacemark]
                if method == "geocode" { results = try await geocoder.geocodeAddressString(a.string("address")) }
                else {
                    let coord = CLLocationCoordinate2D(latitude:try a.number("latitude"),longitude:try a.number("longitude"))
                    guard CLLocationCoordinate2DIsValid(coord) else { throw SDKFailure.invalid("coordinates") }
                    results = try await geocoder.reverseGeocodeLocation(CLLocation(latitude:coord.latitude,longitude:coord.longitude))
                }
                return results.map { p -> [String:Any] in
                    var data: [String:Any] = ["name":p.name ?? "", "city":p.locality ?? "", "country":p.country ?? "", "street":p.thoroughfare ?? ""]
                    if let point = p.location { data["latitude"] = point.coordinate.latitude; data["longitude"] = point.coordinate.longitude }
                    return data
                }
            } onCancel: { geocoder.cancelGeocode() }
        }
        try await authorize()
        let precision = try a.choice("accuracy",["best","nearestTenMeters","hundredMeters","kilometer"],"hundredMeters")
        manager.desiredAccuracy = ["best":kCLLocationAccuracyBest,"nearestTenMeters":kCLLocationAccuracyNearestTenMeters,"hundredMeters":kCLLocationAccuracyHundredMeters,"kilometer":kCLLocationAccuracyKilometer][precision]!
        let id = UUID().uuidString
        if method == "current" {
            let wait = SDKWait<CLLocation>()
            positions[id] = wait; updateStreams()
            defer { positions[id] = nil; updateStreams() }
            return try await location(wait.value())
        }
        events = s.events
        if method == "heading" {
            guard CLLocationManager.headingAvailable() else { throw SDKFailure.unavailable("此设备没有可用的航向传感器") }
            headings.insert(id)
        } else { watchers.insert(id) }
        updateStreams()
        return s.events.add(id) { [weak self] in self?.headings.remove(id); self?.watchers.remove(id); self?.updateStreams() }
    }
    func close() {
        authorization?.finish(.failure(CancellationError())); authorization = nil
        for wait in positions.values { wait.finish(.failure(CancellationError())) }
        positions.removeAll(); headings.removeAll(); watchers.removeAll(); updateStreams()
        manager.delegate = nil
    }
}

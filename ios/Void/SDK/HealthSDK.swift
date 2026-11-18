import Foundation
import HealthKit

@MainActor
final class HealthSDK: SDKModule {
    private let store = HKHealthStore()
    private let names = ["steps","heartRate","sleep","activeEnergy","exerciseMinutes","workouts","activitySummary"]
    private func type(_ name: String) throws -> HKObjectType {
        switch name {
        case "steps": return HKQuantityType(.stepCount)
        case "heartRate": return HKQuantityType(.heartRate)
        case "activeEnergy": return HKQuantityType(.activeEnergyBurned)
        case "exerciseMinutes": return HKQuantityType(.appleExerciseTime)
        case "sleep": return HKCategoryType(.sleepAnalysis)
        case "workouts": return HKObjectType.workoutType()
        case "activitySummary": return HKObjectType.activitySummaryType()
        default: throw SDKFailure.invalid("type")
        }
    }
    private func unit(_ name: String) -> HKUnit {
        switch name { case "heartRate":return .count().unitDivided(by:.minute()); case "activeEnergy":return .kilocalorie(); case "exerciseMinutes":return .minute(); default:return .count() }
    }
    private func request(_ types: [HKObjectType], write: Bool) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw SDKFailure.unavailable("此设备的健康数据不可用") }
        let writable = types.compactMap { $0 as? HKSampleType }
        guard !write || writable.count == types.count else { throw SDKFailure.unavailable("该健康类型为只读") }
        try await store.requestAuthorization(toShare:write ? Set(writable) : [],read:write ? [] : Set(types))
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if method == "available" { return HKHealthStore.isHealthDataAvailable() }
        if method == "types" { return names }
        if method == "authorizeRead" || method == "authorizeWrite" {
            let requested = try a.strings("types")
            guard !requested.isEmpty else { throw SDKFailure.invalid("types") }
            try await request(requested.map(type),write:method == "authorizeWrite")
            return NSNull()
        }
        let name = try a.string("type"), type = try self.type(name)
        if method == "authorization" {
            let state = store.authorizationStatus(for:type)
            return ["read":"notDisclosed","write":state == .sharingAuthorized ? "authorized" : (state == .sharingDenied ? "denied" : "notDetermined")]
        }
        try await request([type],write:method == "write")
        let start = try a.date("startDate"), end = try a.date("endDate")
        guard end >= start else { throw SDKFailure.invalid("endDate") }
        if method == "query" {
            let limit = try a.int("limit",100,range:1...2000)
            if name == "activitySummary" {
                let cal = Calendar.current, units: Set<Calendar.Component> = [.era,.year,.month,.day,.calendar]
                let pred = HKQuery.predicate(forActivitySummariesBetweenStart:cal.dateComponents(units,from:start),end:cal.dateComponents(units,from:end))
                let wait = SDKWait<[HKActivitySummary]>()
                let query = HKActivitySummaryQuery(predicate:pred) { _, summaries, error in Task { @MainActor in
                    if let error { wait.finish(.failure(error)) } else { wait.finish(.success(summaries ?? [])) }
                } }
                store.execute(query); defer { store.stop(query) }
                return try await wait.value().prefix(limit).map { value -> [String:Any] in
                    ["date":cal.date(from:value.dateComponents(for:cal))?.ISO8601Format() ?? "",
                     "kilocalories":value.activeEnergyBurned.doubleValue(for:.kilocalorie()),"exerciseMinutes":value.appleExerciseTime.doubleValue(for:.minute()),
                     "standHours":value.appleStandHours.doubleValue(for:.count())]
                }
            }
            guard let sampleType = type as? HKSampleType else { throw SDKFailure.invalid("type") }
            let wait = SDKWait<[HKSample]>()
            let query = HKSampleQuery(sampleType:sampleType,predicate:HKQuery.predicateForSamples(withStart:start,end:end),limit:limit,
                                      sortDescriptors:[NSSortDescriptor(key:HKSampleSortIdentifierStartDate,ascending:false)]) { _, samples, error in
                Task { @MainActor in if let error { wait.finish(.failure(error)) } else { wait.finish(.success(samples ?? [])) } }
            }
            store.execute(query); defer { store.stop(query) }
            return try await wait.value().map { sample -> [String:Any] in
                var result: [String:Any] = ["id":sample.uuid.uuidString, "startDate":sample.startDate.ISO8601Format(), "endDate":sample.endDate.ISO8601Format(),"type":name]
                if let q = sample as? HKQuantitySample { result["value"] = q.quantity.doubleValue(for:unit(name)); result["unit"] = unit(name).unitString }
                if let c = sample as? HKCategorySample { result["value"] = c.value }
                if let w = sample as? HKWorkout { result["activity"] = w.workoutActivityType.rawValue; result["duration"] = w.duration
                    result["meters"] = w.totalDistance?.doubleValue(for:.meter()); result["kilocalories"] = w.totalEnergyBurned?.doubleValue(for:.kilocalorie()) }
                return result
            }
        }
        guard store.authorizationStatus(for:type) == .sharingAuthorized else { throw SDKFailure.denied("系统没有授予此类型的写入权限") }
        let sample: HKSample
        if let quantity = type as? HKQuantityType {
            let value = try a.number("value"); guard value >= 0 else { throw SDKFailure.invalid("value") }
            sample = HKQuantitySample(type:quantity,quantity:HKQuantity(unit:unit(name),doubleValue:value),start:start,end:end)
        } else if let category = type as? HKCategoryType {
            let value = try a.int("value",range:0...5)
            sample = HKCategorySample(type:category,value:value,start:start,end:end)
        } else if name == "workouts" {
            guard let activity = HKWorkoutActivityType(rawValue:UInt(try a.int("activity"))) else { throw SDKFailure.invalid("activity") }
            let config = HKWorkoutConfiguration(); config.activityType = activity
            let builder = HKWorkoutBuilder(healthStore:store,configuration:config,device:.local())
            do {
                try await builder.beginCollection(at:start)
                try await builder.endCollection(at:end)
                guard let workout = try await builder.finishWorkout() else { throw SDKFailure("HEALTH_ERROR","未能保存运动记录") }
                return workout.uuid.uuidString
            } catch { builder.discardWorkout(); throw error }
        } else { throw SDKFailure.unavailable("该类型为只读") }
        try await store.save(sample)
        return sample.uuid.uuidString
    }
}

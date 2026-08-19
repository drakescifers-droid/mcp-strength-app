//
//  HealthStore.swift
//  MCPStrength
//
//  The HealthKit half: a protocol the app talks to, and the one live
//  conformance that talks to `HKHealthStore`.
//
//  Same boundary as `SyncTransport`, drawn for the same reason. HealthKit
//  cannot be exercised in a unit test — it needs an entitlement, a real store,
//  a permission prompt nobody can tap, and on the simulator a Health app that
//  may not exist. Behind a protocol, everything that DECIDES is testable and
//  only the framework calls are not.
//
//  ## Authorization is not the only "is this on?" flag
//
//  iOS never lets an app revoke its own Health permission, so a stored
//  `writeWorkoutsToHealth` preference sits beside authorization. Both have
//  to be true for a write to happen: permitted AND switched on, which is
//  the reference app's model. Turning the switch off happens here; turning
//  the permission off still happens in Health.
//
//  ## Why we now READ Active Energy, and only that
//
//  Workouts still go OUT and never come back. What we read is
//  `activeEnergyBurned` in the workout's own interval, so a Watch that was
//  already recording can be ASSOCIATED with our entry rather than doubled
//  by our estimate. `HealthWorkoutRule.energyAction` is the decision;
//  this file is the query, the attach, and the fallback if attach throws.
//
//  ## Backfill asks the same question as idempotency, for every id
//
//  `alreadyWritten` is "does Health have THIS workout?" at finish. Settings
//  needs the inverse for every finished workout, so `writtenExternalIDs`
//  is the same source predicate without the id filter. A failed query
//  throws rather than returning empty: empty means "none of ours", and
//  treating a failure as empty would offer Add for the whole history
//  and then duplicate it.
//
//  `NSHealthShareUsageDescription` covers Active Energy AND the four
//  measurement types we actually query. Asking to read anything we do
//  not query is a permission prompt that cannot be honestly explained.
//  Read status is NOT checkable — `authorizationStatus(for:)` only
//  reports sharing — so a denied energy read looks like "no samples"
//  and we keep the estimate, and a denied measurement read looks like
//  Health has nothing to import.
//
//  ## TWO write types, and they are authorized separately
//
//  A workout, and — when the user has chosen a `WorkoutCalorieRate` other than
//  `none` — an `activeEnergyBurned` sample attached to it. iOS asks about the
//  two independently and Health lets them be switched independently
//  afterwards, so "may I write workouts" does NOT answer "may I write energy".
//
//  **Both statuses are therefore checked before writing, and energy is
//  skipped rather than allowed to fail the whole write.** Adding a sample of a
//  type the app is not permitted to share makes `finishWorkout` throw, which
//  would lose the WORKOUT because of a permission about its energy — trading a
//  whole record for an estimate.
//

import Foundation
import HealthKit
import Observation

/// The three things this app needs from Health.
///
/// `@MainActor` because the callers are views and the engine-equivalent, and
/// because `HKHealthStore` has no isolation of its own to respect.
@MainActor
protocol HealthWriting: AnyObject {
    /// Whether HealthKit exists at all. False on iPad and in some simulators,
    /// and a hard no rather than an error to recover from.
    var isAvailable: Bool { get }

    /// Whether the user has allowed workout writing on THIS device.
    ///
    /// > **`.notDetermined` does NOT mean "denied".** It means never asked. The
    /// > two have to stay distinguishable or the settings screen cannot tell
    /// > "tap to allow" from "you turned this off in Health", which are
    /// > different sentences with different next steps.
    var workoutSharingStatus: HealthSharingStatus { get }

    /// Whether the user has allowed ACTIVE ENERGY writing on this device.
    ///
    /// Separate from `workoutSharingStatus` because iOS asks about the two
    /// types separately and Health lets them be turned off separately. A
    /// settings screen that offers a calorie rate while this is `.denied`
    /// would be offering a control that cannot do anything — the shape of the
    /// rest-timer bug from the 2026-08-18 gym session.
    var activeEnergySharingStatus: HealthSharingStatus { get }

    /// Ask for permission to write workouts and their energy. Safe to call
    /// when already authorized; iOS shows the sheet at most once per type.
    func requestWorkoutAuthorization() async throws

    /// Write this workout, unless Health already has it.
    ///
    /// `rate` is required so this layer can ask `energyAction` rather than
    /// re-deriving attach-vs-estimate from the plan's estimate field. The
    /// plan still carries that field because a nil there is `none`; the
    /// Bool about existing samples is a query this protocol's caller cannot
    /// run.
    ///
    /// `workoutsEnabled` is the in-app toggle, separate from authorization.
    /// Both must be true. Skipping here rather than throwing keeps a turned-
    /// off switch from failing the end of a session.
    ///
    /// Returns whether anything was written, so a caller can tell a real write
    /// from a correctly-skipped duplicate.
    @discardableResult
    func writeWorkout(
        _ plan: HealthWorkoutPlan,
        rate: WorkoutCalorieRate,
        workoutsEnabled: Bool
    ) async throws -> Bool

    /// The `HKMetadataKeyExternalUUID` values this app has already written.
    ///
    /// The other half of `alreadyWritten`: that call asks about ONE id at
    /// finish time (limit 1). This asks about ALL of them, so Settings can
    /// subtract and offer backfill. Same source predicate — another app's
    /// workout that happens to carry the same metadata key is not ours.
    ///
    /// Throws rather than returning `[]` on a failed query. Empty means
    /// "Health has none of ours"; a failure is "we could not ask", and those
    /// must stay distinguishable or the banner would offer Add for every
    /// finished workout when Health is unreachable, then duplicate them.
    func writtenExternalIDs() async throws -> Set<UUID>

    /// Whether the user has allowed writing the four measurement quantity
    /// types. Combined: if any type is still unasked, this is `.notDetermined`
    /// so Settings can show Allow; if all four are authorized, `.authorized`.
    var measurementSharingStatus: HealthSharingStatus { get }

    /// Ask to write AND read Weight, Body Fat %, Caloric Intake and Waist.
    /// Read is in the same prompt as write so Settings does not have a
    /// second Allow for types it is about to query. Asking to read a type
    /// we do not query is a permission prompt that cannot be honestly
    /// explained — we query exactly these four.
    func requestMeasurementAuthorization() async throws

    /// Write this measurement sample, unless Health already has it.
    ///
    /// `enabled` is the in-app write toggle. Both it and authorization must
    /// be true. Skipping rather than throwing keeps a turned-off switch
    /// from failing a Save.
    @discardableResult
    func writeMeasurement(
        _ plan: HealthMeasurementPlan,
        enabled: Bool
    ) async throws -> Bool

    /// The `HKMetadataKeyExternalUUID` values this app has already written
    /// as measurement samples (the four quantity types).
    ///
    /// Same contract as `writtenExternalIDs` for workouts: throws rather
    /// than returning `[]` on a failed query, because empty means "Health
    /// has none of ours" and a failure must not offer Add for every local
    /// Weight and then duplicate them.
    func writtenMeasurementExternalIDs() async throws -> Set<UUID>

    /// Every sample of the four measurement types, reduced to facts the
    /// import rule can decide on. Includes other apps' samples — skipping
    /// ours is `importPlan`'s job (`isFromThisApp`).
    ///
    /// Throws on a failed query rather than returning empty: empty means
    /// "Health has nothing to offer", which would hide a banner that should
    /// have shown, or worse, look like a successful empty scan.
    func measurementSampleFacts() async throws -> [HealthMeasurementSampleFacts]
}

/// Mirrors `HKAuthorizationStatus` without exposing HealthKit to the rest of
/// the app — the same reason `ServerRefusal` exists in the sync engine.
enum HealthSharingStatus: Equatable, Hashable, Sendable {
    /// Never asked.
    case notDetermined
    /// Asked, and allowed.
    case authorized
    /// Asked, and refused — or turned off later in Apple Health.
    case denied
    /// No HealthKit on this device.
    case unavailable
}

// MARK: - The live store

@MainActor
@Observable
final class HealthStore: HealthWriting {

    private let store = HKHealthStore()

    /// The two types this app writes. Declared once so the authorization
    /// request and the write cannot drift apart — asking for one set and
    /// writing another is an authorization error at runtime and nowhere else.
    private static let workoutType = HKObjectType.workoutType()
    private static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private static let measurementTypes: [HKQuantityType] = [
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.waistCircumference),
    ]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var workoutSharingStatus: HealthSharingStatus {
        status(of: Self.workoutType)
    }

    var activeEnergySharingStatus: HealthSharingStatus {
        status(of: Self.activeEnergyType)
    }

    var measurementSharingStatus: HealthSharingStatus {
        guard isAvailable else { return .unavailable }
        let statuses = Self.measurementTypes.map { status(of: $0) }
        if statuses.contains(.notDetermined) { return .notDetermined }
        if statuses.allSatisfy({ $0 == .authorized }) { return .authorized }
        if statuses.contains(.denied) { return .denied }
        return .notDetermined
    }

    private func status(of type: HKObjectType) -> HealthSharingStatus {
        guard isAvailable else { return .unavailable }
        switch store.authorizationStatus(for: type) {
        case .notDetermined:       return .notDetermined
        case .sharingAuthorized:   return .authorized
        case .sharingDenied:       return .denied
        @unknown default:          return .notDetermined
        }
    }

    func requestWorkoutAuthorization() async throws {
        guard isAvailable else { return }
        // Write types and the one read type in ONE prompt. Asking for energy
        // later, at the moment a workout is being written, would put a
        // permission sheet on top of the end of a training session. The read
        // is Active Energy only — see the file comment.
        try await store.requestAuthorization(
            toShare: [Self.workoutType, Self.activeEnergyType],
            read: [Self.activeEnergyType]
        )
    }

    func requestMeasurementAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(
            toShare: Set(Self.measurementTypes),
            read: Set(Self.measurementTypes)
        )
    }

    @discardableResult
    func writeMeasurement(
        _ plan: HealthMeasurementPlan,
        enabled: Bool
    ) async throws -> Bool {
        guard isAvailable else { return false }
        guard enabled else { return false }
        guard measurementSharingStatus == .authorized else { return false }

        let sampleType = Self.quantityType(plan.quantity)
        if try await alreadyWritten(externalID: plan.externalID, sampleType: sampleType) {
            return false
        }

        let sample = HKQuantitySample(
            type: sampleType,
            quantity: HKQuantity(
                unit: Self.unit(plan.quantity),
                doubleValue: plan.canonicalValue
            ),
            start: plan.recordedAt,
            end: plan.recordedAt,
            metadata: [HKMetadataKeyExternalUUID: plan.externalID.uuidString]
        )
        try await store.save(sample)
        return true
    }

    func writtenMeasurementExternalIDs() async throws -> Set<UUID> {
        let mine = HKQuery.predicateForObjects(from: .default())
        var ids: Set<UUID> = []
        for type in Self.measurementTypes {
            let samples = try await samples(of: type, matching: mine, limit: HKObjectQueryNoLimit)
            for sample in samples {
                guard
                    let raw = sample.metadata?[HKMetadataKeyExternalUUID] as? String,
                    let id = UUID(uuidString: raw)
                else { continue }
                ids.insert(id)
            }
        }
        return ids
    }

    func measurementSampleFacts() async throws -> [HealthMeasurementSampleFacts] {
        var facts: [HealthMeasurementSampleFacts] = []
        for quantity in HealthMeasurementQuantity.allCases {
            let type = Self.quantityType(quantity)
            let unit = Self.unit(quantity)
            let samples = try await samples(of: type, matching: nil, limit: HKObjectQueryNoLimit)
            for sample in samples {
                guard let quantitySample = sample as? HKQuantitySample else { continue }
                let external: UUID?
                if let raw = quantitySample.metadata?[HKMetadataKeyExternalUUID] as? String {
                    external = UUID(uuidString: raw)
                } else {
                    external = nil
                }
                facts.append(
                    HealthMeasurementSampleFacts(
                        isFromThisApp: quantitySample.sourceRevision.source == HKSource.default(),
                        sampleID: quantitySample.uuid,
                        externalID: external,
                        quantity: quantity,
                        canonicalValue: quantitySample.quantity.doubleValue(for: unit),
                        recordedAt: quantitySample.startDate
                    )
                )
            }
        }
        return facts
    }

    private static func quantityType(_ quantity: HealthMeasurementQuantity) -> HKQuantityType {
        switch quantity {
        case .bodyMass:                 HKQuantityType(.bodyMass)
        case .bodyFatPercentage:        HKQuantityType(.bodyFatPercentage)
        case .dietaryEnergyConsumed:    HKQuantityType(.dietaryEnergyConsumed)
        case .waistCircumference:       HKQuantityType(.waistCircumference)
        }
    }

    private static func unit(_ quantity: HealthMeasurementQuantity) -> HKUnit {
        switch quantity {
        case .bodyMass:                 .gramUnit(with: .kilo)
        case .bodyFatPercentage:        .percent()
        case .dietaryEnergyConsumed:    .kilocalorie()
        case .waistCircumference:       .meter()
        }
    }

    @discardableResult
    func writeWorkout(
        _ plan: HealthWorkoutPlan,
        rate: WorkoutCalorieRate,
        workoutsEnabled: Bool
    ) async throws -> Bool {
        guard isAvailable else { return false }
        guard workoutsEnabled else { return false }
        guard workoutSharingStatus == .authorized else { return false }

        // IDEMPOTENCY, asked of Health rather than remembered locally. See
        // HealthWorkoutRule for why there is no flag on the model.
        if try await alreadyWritten(externalID: plan.externalID) { return false }

        let configuration = HKWorkoutConfiguration()
        // Traditional rather than functional: this is barbells, dumbbells and
        // machines. Apple's own split puts circuit-style work under functional.
        configuration.activityType = .traditionalStrengthTraining

        // `HKWorkoutBuilder`, not `HKWorkout(activityType:start:end:)`. EVERY
        // one of those initialisers is `API_DEPRECATED("Use HKWorkoutBuilder",
        // ios(8.0, 17.0))` — read out of HKWorkout.h in the SDK, not recalled.
        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )

        try await builder.beginCollection(at: plan.start)

        // ENERGY. The rule decides; this layer queries, attaches, or writes.
        // Skipping rather than throwing is the decision in the file comment —
        // losing the workout over its energy would be trading a record for an
        // estimate. No distance sample: nothing here measures distance
        // (AGENTS.md rule 4).
        try await addEnergy(to: builder, plan: plan, rate: rate)

        try await builder.addMetadata([HKMetadataKeyExternalUUID: plan.externalID.uuidString])
        try await builder.endCollection(at: plan.end)
        _ = try await builder.finishWorkout()
        return true
    }

    /// Query, then follow `HealthWorkoutRule.energyAction`. Attach-throw is
    /// the unproven HealthKit fact: we catch it and write the estimate rather
    /// than losing energy, or the workout. A failed query is treated as no
    /// samples — same as a denied read, which iOS will not report as a status.
    private func addEnergy(
        to builder: HKWorkoutBuilder,
        plan: HealthWorkoutPlan,
        rate: WorkoutCalorieRate
    ) async throws {
        let existing: [HKSample]
        do {
            existing = try await activeEnergySamples(from: plan.start, to: plan.end)
        } catch {
            existing = []
        }

        var action = HealthWorkoutRule.energyAction(
            rate: rate,
            existingSamplesInInterval: !existing.isEmpty,
            forSeconds: plan.duration
        )

        if case .attachExisting = action {
            do {
                try await builder.addSamples(existing)
                return
            } catch {
                action = HealthWorkoutRule.afterAttachFailure(action)
            }
        }

        switch action {
        case .none, .attachExisting:
            return
        case .writeEstimate(let kilocalories):
            try await addEstimate(to: builder, kilocalories: kilocalories, plan: plan)
        }
    }

    /// Our flat-rate sample, only when Health permits writing energy.
    /// Permission is checked here rather than before attach: associating
    /// Watch samples is not writing a number of our own, so a denied share
    /// should not block attach, only the fallback.
    private func addEstimate(
        to builder: HKWorkoutBuilder,
        kilocalories: Double,
        plan: HealthWorkoutPlan
    ) async throws {
        guard activeEnergySharingStatus == .authorized else { return }
        let sample = HKQuantitySample(
            type: Self.activeEnergyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
            // Spread across the whole workout rather than stamped at one
            // instant: Apple Fitness reads energy against the period it was
            // spent in, and a sample an hour wide that claims one second is
            // a spike in somebody's day that never happened.
            start: plan.start,
            end: plan.end
        )
        try await builder.addSamples([sample])
    }

    /// `activeEnergyBurned` overlapping `[start, end]`. Empty options mean
    /// overlap rather than a strict start, because Watch samples are a
    /// continuous stream and a sample that began a few seconds before the
    /// workout still belongs to it.
    private func activeEnergySamples(from start: Date, to end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.activeEnergyType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// Whether Health already holds a workout this app wrote for this id.
    ///
    /// Scoped to THIS APP's samples (`HKQuery.predicateForObjects(from:)` with
    /// the default source) as well as the external id: another app's workout
    /// that happens to carry the same metadata key is not ours to deduplicate
    /// against, and a shared id is not impossible.
    private func alreadyWritten(externalID: UUID) async throws -> Bool {
        try await alreadyWritten(externalID: externalID, sampleType: .workoutType())
    }

    private func alreadyWritten(
        externalID: UUID,
        sampleType: HKSampleType
    ) async throws -> Bool {
        let mine = HKQuery.predicateForObjects(from: .default())
        let sameID = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: externalID.uuidString
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [mine, sameID])
        let samples = try await samples(of: sampleType, matching: predicate, limit: 1)
        return !samples.isEmpty
    }

    func writtenExternalIDs() async throws -> Set<UUID> {
        let mine = HKQuery.predicateForObjects(from: .default())
        let samples = try await samples(of: .workoutType(), matching: mine, limit: HKObjectQueryNoLimit)
        var ids: Set<UUID> = []
        for sample in samples {
            guard
                let raw = sample.metadata?[HKMetadataKeyExternalUUID] as? String,
                let id = UUID(uuidString: raw)
            else { continue }
            ids.insert(id)
        }
        return ids
    }

    private func samples(
        of sampleType: HKSampleType,
        matching predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }
}

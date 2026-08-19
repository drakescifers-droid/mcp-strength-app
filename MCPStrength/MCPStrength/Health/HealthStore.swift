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
//  ## Authorization is the only "is this on?" flag
//
//  There is deliberately no `writeWorkoutsToHealth` setting stored anywhere.
//  HealthKit already keeps a per-device answer to that question, iOS already
//  provides the UI for changing it, and a second flag would be a second source
//  of truth that can disagree with the first — with the app claiming to write
//  while the system silently drops everything.
//
//  The consequence, and it is a real one: **turning it back off happens in
//  Apple Health, not here.** iOS never lets an app revoke its own permission,
//  so a private toggle could only mean "authorized but choosing not to", which
//  is a distinction with no user-visible meaning today. If a reason for one
//  appears, that is the moment to add it — see the reference app's Apple Health
//  screen, which does carry per-type switches.
//
//  ## Why write-only, and why that shows up in the entitlement
//
//  Workouts go out; nothing comes in. `NSHealthShareUsageDescription` is
//  therefore ABSENT from the build settings and the read set below is empty —
//  asking to READ Health data while never reading it is a permission prompt
//  that cannot be honestly explained.
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
    /// Returns whether anything was written, so a caller can tell a real write
    /// from a correctly-skipped duplicate.
    @discardableResult
    func writeWorkout(_ plan: HealthWorkoutPlan) async throws -> Bool
}

/// Mirrors `HKAuthorizationStatus` without exposing HealthKit to the rest of
/// the app — the same reason `ServerRefusal` exists in the sync engine.
enum HealthSharingStatus: Equatable, Sendable {
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

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var workoutSharingStatus: HealthSharingStatus {
        status(of: Self.workoutType)
    }

    var activeEnergySharingStatus: HealthSharingStatus {
        status(of: Self.activeEnergyType)
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
        // BOTH types in ONE prompt. Asking for energy later, at the moment a
        // workout is being written, would put a permission sheet on top of the
        // end of a training session.
        //
        // Empty read set: this app does not read Health. See the file comment.
        try await store.requestAuthorization(
            toShare: [Self.workoutType, Self.activeEnergyType],
            read: []
        )
    }

    @discardableResult
    func writeWorkout(_ plan: HealthWorkoutPlan) async throws -> Bool {
        guard isAvailable else { return false }
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

        // ENERGY, when the user has asked for it and Health permits it. Both
        // conditions are real and neither implies the other: `nil` is
        // `WorkoutCalorieRate.none` (the user's choice), `.denied` is the
        // permission (the system's). Skipping rather than throwing is the
        // decision argued in the file comment — losing the workout over its
        // energy would be trading a record for an estimate.
        //
        // No distance sample: nothing here measures distance, and that number
        // WOULD be invented (AGENTS.md rule 4).
        if let kilocalories = plan.activeEnergyKilocalories,
           activeEnergySharingStatus == .authorized {
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

        try await builder.addMetadata([HKMetadataKeyExternalUUID: plan.externalID.uuidString])
        try await builder.endCollection(at: plan.end)
        _ = try await builder.finishWorkout()
        return true
    }

    /// Whether Health already holds a workout this app wrote for this id.
    ///
    /// Scoped to THIS APP's samples (`HKQuery.predicateForObjects(from:)` with
    /// the default source) as well as the external id: another app's workout
    /// that happens to carry the same metadata key is not ours to deduplicate
    /// against, and a shared id is not impossible.
    private func alreadyWritten(externalID: UUID) async throws -> Bool {
        let mine = HKQuery.predicateForObjects(from: .default())
        let sameID = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: externalID.uuidString
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [mine, sameID])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: !(samples ?? []).isEmpty)
                }
            }
            store.execute(query)
        }
    }
}

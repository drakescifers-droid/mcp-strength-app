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

    /// Ask for permission to write workouts. Safe to call when already
    /// authorized; iOS shows the sheet at most once per type.
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

    /// The one type this app writes. Declared once so the authorization
    /// request and the write cannot drift apart — asking for one set and
    /// writing another is an authorization error at runtime and nowhere else.
    private static let workoutType = HKObjectType.workoutType()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var workoutSharingStatus: HealthSharingStatus {
        guard isAvailable else { return .unavailable }
        switch store.authorizationStatus(for: Self.workoutType) {
        case .notDetermined:       return .notDetermined
        case .sharingAuthorized:   return .authorized
        case .sharingDenied:       return .denied
        @unknown default:          return .notDetermined
        }
    }

    func requestWorkoutAuthorization() async throws {
        guard isAvailable else { return }
        // Empty read set: this app does not read Health. See the file comment.
        try await store.requestAuthorization(toShare: [Self.workoutType], read: [])
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
        // No energy and no distance samples are added, deliberately — see the
        // note at the bottom of HealthWorkoutRule.swift. A fabricated zero in
        // Apple Fitness is worse than an honest absence.
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

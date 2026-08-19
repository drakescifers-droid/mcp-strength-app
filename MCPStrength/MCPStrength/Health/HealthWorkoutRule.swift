//
//  HealthWorkoutRule.swift
//  MCPStrength
//
//  What a finished workout becomes in Apple Health — as a pure rule, with no
//  HealthKit types in sight.
//
//  Same split as `SyncPlanning` versus `SyncClient`, and for the same reason:
//  the decisions are where data is silently lost or duplicated, and they are
//  testable here with no HKHealthStore, no entitlement, no permission prompt
//  and no device. `HealthStore.swift` is the part that talks to the framework.
//
//  ## One direction, on purpose
//
//  Workouts go OUT to Health and never come back. `02-architecture.md` flags
//  the echo loop as the trap to design for up front — write to Health, Health
//  notifies observers, the app imports its own write as new data, duplicates
//  forever. **A one-way path cannot have that bug at all**, which is why
//  workouts are the half that shipped first. Measurements, which really are
//  bidirectional, land on this plumbing afterwards and inherit a proven
//  permission and settings path.
//
//  ## Idempotency without a new column
//
//  A workout must not appear twice in Health because it was finished, reopened
//  and finished again, or because a second device also has it.
//
//  The obvious fix — a `didWriteToHealth` flag on `Workout` — was rejected. It
//  is a new stored property on a synced model (the crash-on-launch rule), it
//  needs a Postgres column to travel, and it would still be WRONG across
//  devices: Health syncs through iCloud, so the entry can already be there
//  while a second phone's flag says otherwise.
//
//  Instead the workout's own id goes into the sample's
//  `HKMetadataKeyExternalUUID`, which is the platform's purpose-built field for
//  exactly this, and the writer queries for that id before writing. No schema
//  change on either side, and it is correct across devices because it asks
//  Health what Health already has rather than remembering what we did.
//

import Foundation

/// Everything needed to write one workout to Health, with no HealthKit types.
struct HealthWorkoutPlan: Equatable, Sendable {
    /// The workout's own id, written to `HKMetadataKeyExternalUUID` so the
    /// entry can be found again without storing anything locally.
    let externalID: UUID
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum HealthWorkoutRule {

    /// Why a workout is not going to Health. Returned rather than a bare `nil`
    /// so a caller — or a test — can tell "nothing to do" from "something is
    /// wrong", which a single nil collapses into one indistinguishable case.
    enum Ineligible: Error, Equatable, Sendable {
        /// Still in progress. A workout in flight is a draft, not a record.
        case unfinished
        /// Tombstoned. It did not happen as far as this app is concerned.
        case deleted
        /// Finished at or before it started. Health rejects a non-positive
        /// interval outright, so catching it here turns a thrown framework
        /// error into a decision with a name.
        case notPositiveDuration
    }

    /// The plan for this workout, or why there isn't one.
    ///
    /// **The eligibility rules mirror `PushFilter.shouldPush(_ workout:)` and
    /// that is deliberate.** Both answer "is this a record of training yet?",
    /// and if they ever disagree the app is telling Health something different
    /// from what it tells its own server. The one difference is that Health
    /// additionally needs a positive interval, because it stores a duration
    /// where the server stores two timestamps.
    static func plan(for workout: Workout) -> Result<HealthWorkoutPlan, Ineligible> {
        if workout.deletedAt != nil { return .failure(.deleted) }
        guard let completedAt = workout.completedAt else { return .failure(.unfinished) }
        guard completedAt > workout.startedAt else { return .failure(.notPositiveDuration) }

        return .success(
            HealthWorkoutPlan(
                externalID: workout.id,
                start: workout.startedAt,
                end: completedAt
            )
        )
    }
}

// MARK: - What is deliberately NOT in the plan

//  **ENERGY BURNED IS ABSENT, and that is a decision rather than a gap.**
//
//  Nothing in this app computes calories. It has no heart rate, no body mass on
//  the workout, and no METs table — every number it could put in that field
//  would be invented. `HKWorkoutBuilder` is perfectly happy to write a workout
//  with no energy sample, and Fitness shows it as a workout with no energy.
//
//  Writing `0` instead would be worse than writing nothing: Apple Fitness would
//  render "0 calories" against an hour of squatting, which reads as a
//  measurement rather than an absence. That is AGENTS.md rule 4 — never display
//  a fabricated zero — applied to somebody else's UI, where we cannot add a
//  caveat and cannot take it back.
//
//  This is the field to revisit if the app ever gains body mass (it has a
//  Weight measurement type) and a defensible MET estimate. Until then, absent
//  is the honest answer.
//
//  **TOTAL VOLUME IS ALSO ABSENT.** `Workout.totalVolume` is kilograms×reps,
//  which is a real number this app does compute — but Health has no type for
//  it, and the nearest quantity types all mean something else. Inventing a
//  mapping would put a number in a field whose name promises something it is
//  not.

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

    /// Active energy to attach, in kilocalories — or `nil` for no energy
    /// sample at all.
    ///
    /// **`nil` and `0` are different instructions and must stay different.**
    /// Nil means "write a workout with no energy", which is what this app did
    /// before the rate existed and what `WorkoutCalorieRate.none` still asks
    /// for. Zero would be a sample claiming an hour of squatting burned
    /// nothing — a fabricated measurement in somebody else's UI, where no
    /// caveat can be added and it cannot be taken back (AGENTS.md rule 4).
    let activeEnergyKilocalories: Double?

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
    ///
    /// `rate` is REQUIRED rather than defaulted, so that a caller which has not
    /// read `AppSettings` cannot silently write energy at somebody else's
    /// setting. The compiler asks the question at every call site; a default
    /// would answer it wrong exactly once, invisibly.
    static func plan(
        for workout: Workout,
        rate: WorkoutCalorieRate
    ) -> Result<HealthWorkoutPlan, Ineligible> {
        if workout.deletedAt != nil { return .failure(.deleted) }
        guard let completedAt = workout.completedAt else { return .failure(.unfinished) }
        guard completedAt > workout.startedAt else { return .failure(.notPositiveDuration) }

        return .success(
            HealthWorkoutPlan(
                externalID: workout.id,
                start: workout.startedAt,
                end: completedAt,
                activeEnergyKilocalories: energy(
                    forSeconds: completedAt.timeIntervalSince(workout.startedAt),
                    at: rate
                )
            )
        )
    }

    /// Kilocalories for a workout of this length at this rate, or `nil` when
    /// there is no energy to claim.
    ///
    /// A flat rate per hour, pro-rated by duration. No bodyweight, no METs, no
    /// heart rate — the whole point of the reference app's design is that the
    /// user supplies the estimate and the app does nothing but scale it by how
    /// long they trained.
    ///
    /// **`none` returns nil rather than 0**, which is the one branch here that
    /// matters: see `HealthWorkoutPlan.activeEnergyKilocalories`.
    static func energy(forSeconds seconds: TimeInterval, at rate: WorkoutCalorieRate) -> Double? {
        guard rate != .none else { return nil }
        guard seconds > 0 else { return nil }
        return rate.kilocaloriesPerHour * seconds / 3600
    }
}

// MARK: - What is deliberately NOT in the plan

//  **ENERGY IS NOW A USER-CHOSEN RATE, and the reversal is worth understanding
//  rather than just reading.** This block used to say energy was absent on
//  purpose, because every number the app could compute would be invented.
//
//  That argument was about the APP inventing a figure. It does not apply to a
//  figure the USER picks: `WorkoutCalorieRate` is the person saying "count my
//  lifting at roughly 200 kcal an hour", every screen that offers it names the
//  number, and `none` — the behaviour that shipped first — is still a
//  first-class choice. What rule 4 forbids is presenting an unmeasured number
//  as a measurement, not letting somebody state an estimate about their own
//  training.
//
//  What has NOT changed: a fabricated ZERO is still worse than nothing, so
//  `none` produces no sample at all rather than a 0 kcal one.
//
//  ⚠️ **DOUBLE COUNTING IS UNVERIFIED AND IS THE THING TO CHECK ON A DEVICE.**
//  A Watch worn while lifting is already writing `activeEnergyBurned`
//  continuously. Our sample on top may land in the Activity rings twice. The
//  reference app's copy only claims its setting is ignored when logging VIA its
//  Watch app — it says nothing about merely wearing one, and whether Apple
//  deduplicates energy across sources for the rings was never established.
//  Check it in Apple Fitness before trusting the number, and `none` is the
//  honest setting for a Watch wearer until it is.
//
//  The better long-term answer is to ATTACH the Watch's existing samples rather
//  than adding our own — real measured energy, no estimate — and it needs read
//  permission plus a fact nobody has established (whether HealthKit lets an app
//  attach samples another source owns). docs/02-architecture.md § the Health
//  block has both.
//
//  **TOTAL VOLUME IS ALSO ABSENT.** `Workout.totalVolume` is kilograms×reps,
//  which is a real number this app does compute — but Health has no type for
//  it, and the nearest quantity types all mean something else. Inventing a
//  mapping would put a number in a field whose name promises something it is
//  not.

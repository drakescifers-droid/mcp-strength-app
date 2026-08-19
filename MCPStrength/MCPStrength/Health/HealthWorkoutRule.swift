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
//  Energy source is the same shape a second time: whether to attach Watch
//  samples, write our estimate, or write nothing is a function of a rate, a
//  Bool, and a duration. The Bool is a fact the HealthKit layer will report
//  after a query this file cannot run. Importing HealthKit here to "complete"
//  the decision would put the untestable half back into the testable one.
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
    /// **This is the ESTIMATE, always.** Whether that estimate is written,
    /// skipped, or held as a fallback while Watch samples are attached is
    /// `HealthEnergyAction`, decided by `HealthWorkoutRule.energyAction`
    /// after this layer has queried. Collapsing the two would make `none`
    /// and "attach failed" the same instruction, and they are not.
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

/// What to do with energy for one finished workout, given the user's rate
/// and whether Health already has `activeEnergyBurned` in the interval.
///
/// Sits BESIDE `HealthWorkoutPlan`, not on it. The plan is the write payload
/// HealthStore already consumes (`externalID`, interval, the estimate). This
/// is the instruction the HealthKit layer will follow once it can query.
/// Putting the action on the plan would require knowing whether samples
/// exist at `plan(for:rate:)` time, which is a query this rule cannot run;
/// replacing the estimate field with this type would break the caller that
/// still writes that field.
///
/// Three actions, and they are not symmetric:
///
///   * **`none`** — no energy, no attach. Even if Health already has samples.
///     `WorkoutCalorieRate.none` turns energy off, not merely our estimate.
///   * **`attachExisting`** — associate those samples with our workout, and
///     do not write a second number. Carries the estimate so a failed attach
///     still has a number to write.
///   * **`writeEstimate`** — no samples in the interval, rate not `none`.
///     Same figure `HealthWorkoutRule.energy(forSeconds:at:)` already returns.
enum HealthEnergyAction: Equatable, Sendable {
    /// No energy sample at all, and do not attach anything Health already
    /// has. The instruction `WorkoutCalorieRate.none` asked for, and the
    /// instruction a nil estimate produces — including zero duration, which
    /// already makes `energy(forSeconds:at:)` return nil.
    ///
    /// Named `none` to match the rate. It is not `Optional.none`, and a 0 kcal
    /// sample is not this case either: see
    /// `HealthWorkoutPlan.activeEnergyKilocalories`.
    case none

    /// Associate Health's existing `activeEnergyBurned` samples with our
    /// workout rather than writing our own.
    ///
    /// The associated value is the estimate, held in case attaching throws.
    /// That HealthKit fact is unproven on a device (`HKWorkoutBuilder.addSamples`
    /// documents that unsaved samples get saved, not that an app can attach
    /// samples another source owns), and "attach failed" is not the user
    /// asking for no energy. See `HealthWorkoutRule.afterAttachFailure`.
    case attachExisting(fallbackKilocalories: Double)

    /// Write the flat-rate estimate. Same number `energy(forSeconds:at:)`
    /// already returns — a second calorie rule here would be a second number
    /// in Apple Fitness for the same hour of lifting.
    case writeEstimate(kilocalories: Double)
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

    /// Where the calories come from, once we know whether Health already
    /// has `activeEnergyBurned` in the workout's interval.
    ///
    /// A pure function of the user's rate, a Bool the HealthKit layer will
    /// report after a query this rule cannot run, and how long they trained.
    /// `plan(for:rate:)` does not take that Bool and must not: the plan
    /// cannot query HealthKit, and growing it would either invent the answer
    /// or force every existing caller to pretend they have one.
    ///
    /// **`none` is decided before the samples Bool**, and that order is the
    /// whole decision. A rule written as "if samples exist, attach; else
    /// estimate" attaches Watch energy when the user picked None, which
    /// makes the None setting stop meaning off. The nil-estimate path
    /// (rate `none`, or non-positive duration) therefore returns `.none`
    /// regardless of the Bool — same nil `energy(forSeconds:at:)` already
    /// returns, so the source decision cannot disagree with the plan.
    ///
    /// When the estimate exists and so do samples, the estimate is not
    /// discarded — it rides along as the attach fallback. See
    /// `afterAttachFailure`.
    static func energyAction(
        rate: WorkoutCalorieRate,
        existingSamplesInInterval: Bool,
        forSeconds seconds: TimeInterval
    ) -> HealthEnergyAction {
        guard let kilocalories = energy(forSeconds: seconds, at: rate) else {
            return .none
        }
        if existingSamplesInInterval {
            return .attachExisting(fallbackKilocalories: kilocalories)
        }
        return .writeEstimate(kilocalories: kilocalories)
    }

    /// The action to take when attaching existing samples throws.
    ///
    /// Attach-throws is an unproven HealthKit fact (whether an app can
    /// associate samples another source owns). It is not a user choice.
    /// Dropping the number they picked because a Watch sample could not be
    /// associated would lose it silently — trading a stated estimate for a
    /// framework error about someone else's samples.
    ///
    /// The attach case already carries that number, so this is not a second
    /// calorie rule: it is a substitution of actions, attach → estimate, so
    /// a caller cannot retry attach forever by accident. **`none` in stays
    /// `none` out.** A failed attach is not how `none` happens; `none` is
    /// the setting. Calling this on `.none` or on an estimate that was never
    /// going to attach is a no-op so the HealthKit layer can apply it
    /// without first asking which case it has.
    static func afterAttachFailure(_ action: HealthEnergyAction) -> HealthEnergyAction {
        switch action {
        case .attachExisting(let kilocalories):
            return .writeEstimate(kilocalories: kilocalories)
        case .none, .writeEstimate:
            return action
        }
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
//  than adding our own — real measured energy, no estimate. The DECISION is now
//  `HealthEnergyAction` / `energyAction`; the query, the attach, and the
//  read-permission prompt are HealthStore's job. Whether HealthKit lets an
//  app attach samples another source owns is still unproven on a device.
//  docs/02-architecture.md § the Health block has both.
//
//  **TOTAL VOLUME IS ALSO ABSENT.** `Workout.totalVolume` is kilograms×reps,
//  which is a real number this app does compute — but Health has no type for
//  it, and the nearest quantity types all mean something else. Inventing a
//  mapping would put a number in a field whose name promises something it is
//  not.

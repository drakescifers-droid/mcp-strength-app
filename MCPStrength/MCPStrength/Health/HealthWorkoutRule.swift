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
//  ## Backfill is the other half of that decision
//
//  People log workouts, then later grant Health permission (or flip the in-app
//  toggle on). Those older sessions never went out. Because there is no
//  `didWriteToHealth` flag, "what is missing" cannot be a local column — it is
//  the same query that makes the write idempotent, inverted: local workouts
//  that `plan` would accept, whose ids Health does not yet hold.
//
//  `missingFromHealth` answers WHICH rows. `backfillPrompt` answers WHAT the
//  Settings banner says for a count. They stay two functions so the sentence
//  cannot become a second way of counting — a bug in one would then be
//  invisible in the other. The query that fills `alreadyWritten` is
//  HealthStore's job, the same shape as `existingSamplesInInterval` for energy.
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

    /// Finished workouts Health does not yet have an entry for, in training
    /// order.
    ///
    /// The other half of rejecting a `didWriteToHealth` column: because we
    /// ask Health what it already holds rather than remembering what we did,
    /// "what is missing" is the same question inverted. `alreadyWritten` is
    /// the set of this app's `HKMetadataKeyExternalUUID` values — each is a
    /// workout's own id, the same `HealthWorkoutPlan.externalID` the writer
    /// stamps. That set is a fact the HealthKit layer will report after a
    /// query this file cannot run, the same shape as
    /// `existingSamplesInInterval` on `energyAction`. Importing HealthKit
    /// here to "complete" the decision would put the untestable half back
    /// into the testable one.
    ///
    /// **Eligibility is `plan(for:rate:)`, not a second list of reasons.**
    /// An unfinished, tombstoned, or non-positive-duration workout cannot
    /// be "missing from Health" because it will never be written. If this
    /// function and `plan` ever disagreed, the banner would offer Add for
    /// a row `writeWorkout` will refuse.
    ///
    /// The calorie rate does not belong here. Energy is about what gets
    /// attached to a write, not about whether a write should happen. The
    /// call through `plan` still needs a rate (it is required, not
    /// defaulted); `.none` is the cheapest argument and is not a claim
    /// about the energy the eventual write will carry.
    ///
    /// Sorted by `startedAt` ascending so Add writes them in training
    /// order and Apple Fitness's timeline matches the gym, not the order
    /// the local array happened to be in. An unsorted return is a silent
    /// shuffle every time Settings appears.
    ///
    /// An empty `alreadyWritten` means Health has none of ours yet: every
    /// eligible workout is missing. A set that contains a workout's id
    /// means that one is not missing, even if a different workout in the
    /// same list is.
    static func missingFromHealth(
        _ workouts: [Workout],
        alreadyWritten: Set<UUID>
    ) -> [Workout] {
        workouts
            .filter { workout in
                guard !alreadyWritten.contains(workout.id) else { return false }
                if case .success = plan(for: workout, rate: .none) {
                    return true
                }
                return false
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// The sentence the Settings banner shows for this many missing
    /// workouts, or `nil` when there is nothing to show.
    ///
    /// A function of a count, not of the missing array, and that split is
    /// the whole point. If the sentence counted the array itself, a bug in
    /// `missingFromHealth` would produce a matching lie in the banner and
    /// the two tests would agree on the wrong number. The view asks this
    /// with `missing.count`; the two answers have to be composed, not
    /// derived from each other.
    ///
    /// **`count <= 0` is `nil`, not `"0 …"`.** A banner reading "0 workouts
    /// without entries" is a count of absence — AGENTS.md rule 4. The view
    /// that gets nil shows nothing. Negative counts are the same: nothing
    /// in the app should pass one, and treating it as a count would invent
    /// a banner.
    ///
    /// Singular vs plural is load-bearing English, not decoration. "1
    /// workouts" is the kind of lie this project refuses to ship. The
    /// wording is the reference app's ("14 Strong workouts without
    /// corresponding Apple Health entries. Add?") with Strong renamed to
    /// MCP Strength — the app's name, not "Strong", and not dropped. The
    /// Add *button* is drawn by the view; the sentence still asks the
    /// question, matching the screenshot.
    static func backfillPrompt(count: Int) -> String? {
        switch count {
        case ...0:
            return nil
        case 1:
            return "1 MCP Strength workout without a corresponding Apple Health entry. Add workout to Apple Health?"
        default:
            return "\(count) MCP Strength workouts without corresponding Apple Health entries. Add workouts to Apple Health?"
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

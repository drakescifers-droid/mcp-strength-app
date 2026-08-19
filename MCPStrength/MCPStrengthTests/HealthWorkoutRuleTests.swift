//
//  HealthWorkoutRuleTests.swift
//  MCPStrengthTests
//
//  The eligibility rule, which is the whole of what can be tested without a
//  device, an entitlement and somebody's thumb on a permission sheet. That is
//  exactly why the rule is a pure function and `HealthStore` is behind a
//  protocol — the same split as SyncPlanning versus SyncClient.
//
//  What these CANNOT cover, and what therefore has to be checked on the phone:
//  the permission prompt, the write itself, and whether a workout actually
//  appears in Apple Fitness. `docs/04-status.md` § Not verified says so.
//
//  ⚠️ And one more, added with the calorie rate: **whether our energy sample
//  DOUBLE COUNTS against a worn Apple Watch** in the Activity rings. That is a
//  fact about how Apple merges energy from two sources, so no test here can
//  reach it — it has to be looked at in Apple Fitness after a real workout.
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct HealthWorkoutRuleTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, ExercisePreference.self, TemplateFolder.self, Template.self,
            TemplateExercise.self, TemplateSet.self, ProgramDay.self,
            Workout.self, WorkoutExercise.self, WorkoutSet.self,
            MeasurementType.self, MeasurementEntry.self, AppSettings.self,
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func finishedWorkout(in context: ModelContext, minutes: Double = 45) -> Workout {
        let workout = Workout(name: "Evening Workout")
        workout.startedAt = start
        workout.completedAt = start.addingTimeInterval(minutes * 60)
        context.insert(workout)
        return workout
    }

    // MARK: - What goes

    @Test func aFinishedWorkoutBecomesAPlanCarryingItsOwnID() throws {
        let context = try makeContext()
        let workout = finishedWorkout(in: context)

        let plan = try #require(try? HealthWorkoutRule.plan(for: workout, rate: .medium).get())

        // The id is what makes the write idempotent WITHOUT a local flag: it
        // goes into HKMetadataKeyExternalUUID and the writer asks Health
        // whether it already has it. If this ever stopped being the workout's
        // own id, a re-finish would duplicate the entry in Apple Fitness.
        #expect(plan.externalID == workout.id)
        #expect(plan.start == start)
        #expect(plan.end == start.addingTimeInterval(45 * 60))
        #expect(plan.duration == 45 * 60)
    }

    // MARK: - Energy
    //
    // A flat rate per hour the USER picks, pro-rated by how long they trained.
    // No bodyweight, no METs, no heart rate — see WorkoutCalorieRate for why a
    // user-chosen estimate is not the fabricated number rule 4 forbids.

    @Test func energyIsTheChosenRateProRatedByDuration() throws {
        let context = try makeContext()
        let workout = finishedWorkout(in: context, minutes: 45)

        let plan = try #require(try? HealthWorkoutRule.plan(for: workout, rate: .medium).get())

        // 200 kcal/hour for three quarters of an hour.
        #expect(plan.activeEnergyKilocalories == 150)
    }

    @Test func everyRateScalesTheSameWay() throws {
        let context = try makeContext()
        let workout = finishedWorkout(in: context, minutes: 60)

        let expected: [WorkoutCalorieRate: Double] = [
            .low: 150, .medium: 200, .high: 250, .veryHigh: 300,
        ]
        for (rate, kilocalories) in expected {
            let plan = try #require(try? HealthWorkoutRule.plan(for: workout, rate: rate).get())
            #expect(
                plan.activeEnergyKilocalories == kilocalories,
                "\(rate) should claim \(kilocalories) kcal for an hour"
            )
        }
    }

    // THE LOAD-BEARING ONE. `none` must produce NO SAMPLE, not a zero one.
    // A 0 kcal sample is a measurement claiming an hour of squatting burned
    // nothing, written into somebody else's UI where no caveat can be added —
    // AGENTS.md rule 4, and the behaviour this app shipped before the rate
    // existed. A rule written as "multiply by the rate" passes every other
    // test here and silently writes that zero.
    @Test func noneWritesNoEnergySampleAtAllRatherThanZero() throws {
        let context = try makeContext()
        let workout = finishedWorkout(in: context, minutes: 45)

        let plan = try #require(try? HealthWorkoutRule.plan(for: workout, rate: .none).get())

        #expect(plan.activeEnergyKilocalories == nil)
        // Not `== 0`, and the distinction is the whole point: a caller that
        // reads this as a number cannot tell "no energy" from "no calories".
        #expect(plan.activeEnergyKilocalories != 0)
    }

    // The rate is the ONLY thing energy depends on, so a plan built at one rate
    // must not be reusable at another. Stated as a test because the tempting
    // simplification — defaulting the argument — makes exactly this silent.
    @Test func theSameWorkoutClaimsDifferentEnergyAtDifferentRates() throws {
        let context = try makeContext()
        let workout = finishedWorkout(in: context, minutes: 30)

        let low = try #require(try? HealthWorkoutRule.plan(for: workout, rate: .low).get())
        let high = try #require(try? HealthWorkoutRule.plan(for: workout, rate: .high).get())

        #expect(low.activeEnergyKilocalories == 75)
        #expect(high.activeEnergyKilocalories == 125)
        #expect(low != high)
    }

    // A workout that is not written at all has no energy question to answer,
    // and the rate must not turn an ineligible workout into an eligible one.
    @Test func aRateDoesNotMakeAnIneligibleWorkoutEligible() throws {
        let context = try makeContext()
        let unfinished = Workout(name: "In progress")
        unfinished.startedAt = start
        context.insert(unfinished)

        for rate in WorkoutCalorieRate.allCases {
            #expect(HealthWorkoutRule.plan(for: unfinished, rate: rate) == .failure(.unfinished))
        }
    }

    // The five cases are the five values of `public.workout_calorie_rate`, and
    // the numbers are the reference app's. A sixth case added on one side only
    // is an enum mismatch the server rejects at push time — the failure that
    // aborts the whole sync run, because app_settings is first in the order.
    @Test func theRatesAreTheFiveTheServerAccepts() {
        #expect(WorkoutCalorieRate.allCases.map(\.rawValue)
            == ["none", "low", "medium", "high", "veryHigh"])
        #expect(WorkoutCalorieRate.allCases.map(\.kilocaloriesPerHour)
            == [0, 150, 200, 250, 300])
    }

    // MARK: - What does not, and WHY it does not

    // A workout in progress is a draft, not a record — the same reason
    // PushFilter refuses to send one. If these two rules ever disagree the app
    // is telling Health something different from what it tells its own server.
    @Test func anUnfinishedWorkoutIsNotWritten() throws {
        let context = try makeContext()
        let workout = Workout(name: "In progress")
        workout.startedAt = start
        context.insert(workout)

        #expect(HealthWorkoutRule.plan(for: workout, rate: .medium) == .failure(.unfinished))
        #expect(!PushFilter.shouldPush(workout), "the two eligibility rules must agree")
    }

    @Test func aTombstonedWorkoutIsNotWritten() throws {
        let context = try makeContext()
        let workout = finishedWorkout(in: context)
        workout.markDeleted()

        #expect(HealthWorkoutRule.plan(for: workout, rate: .medium) == .failure(.deleted))
    }

    // Health stores a duration where the server stores two timestamps, so a
    // non-positive interval is rejected by the framework. Catching it here
    // turns a thrown framework error into a decision with a name.
    @Test func aZeroLengthWorkoutIsNotWritten() throws {
        let context = try makeContext()
        let workout = Workout(name: "Instant")
        workout.startedAt = start
        workout.completedAt = start
        context.insert(workout)

        #expect(HealthWorkoutRule.plan(for: workout, rate: .medium) == .failure(.notPositiveDuration))
    }

    @Test func aWorkoutFinishingBeforeItStartedIsNotWritten() throws {
        let context = try makeContext()
        let workout = Workout(name: "Backwards")
        workout.startedAt = start
        workout.completedAt = start.addingTimeInterval(-60)
        context.insert(workout)

        #expect(HealthWorkoutRule.plan(for: workout, rate: .medium) == .failure(.notPositiveDuration))
    }

    // MARK: - The reason a Result, not an Optional

    // "Nothing to do" and "something is wrong" are different answers, and a
    // bare nil collapses them into one. A caller that cannot tell an
    // in-progress workout from a corrupt one cannot report either honestly.
    @Test func theReasonsAreDistinguishableFromEachOther() throws {
        let context = try makeContext()
        let unfinished = Workout(name: "A"); unfinished.startedAt = start
        context.insert(unfinished)
        let deleted = finishedWorkout(in: context); deleted.markDeleted()

        let a = HealthWorkoutRule.plan(for: unfinished, rate: .medium)
        let b = HealthWorkoutRule.plan(for: deleted, rate: .medium)
        #expect(a != b)
    }
}

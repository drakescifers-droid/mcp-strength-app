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

        let plan = try #require(try? HealthWorkoutRule.plan(for: workout).get())

        // The id is what makes the write idempotent WITHOUT a local flag: it
        // goes into HKMetadataKeyExternalUUID and the writer asks Health
        // whether it already has it. If this ever stopped being the workout's
        // own id, a re-finish would duplicate the entry in Apple Fitness.
        #expect(plan.externalID == workout.id)
        #expect(plan.start == start)
        #expect(plan.end == start.addingTimeInterval(45 * 60))
        #expect(plan.duration == 45 * 60)
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

        #expect(HealthWorkoutRule.plan(for: workout) == .failure(.unfinished))
        #expect(!PushFilter.shouldPush(workout), "the two eligibility rules must agree")
    }

    @Test func aTombstonedWorkoutIsNotWritten() throws {
        let context = try makeContext()
        let workout = finishedWorkout(in: context)
        workout.markDeleted()

        #expect(HealthWorkoutRule.plan(for: workout) == .failure(.deleted))
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

        #expect(HealthWorkoutRule.plan(for: workout) == .failure(.notPositiveDuration))
    }

    @Test func aWorkoutFinishingBeforeItStartedIsNotWritten() throws {
        let context = try makeContext()
        let workout = Workout(name: "Backwards")
        workout.startedAt = start
        workout.completedAt = start.addingTimeInterval(-60)
        context.insert(workout)

        #expect(HealthWorkoutRule.plan(for: workout) == .failure(.notPositiveDuration))
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

        let a = HealthWorkoutRule.plan(for: unfinished)
        let b = HealthWorkoutRule.plan(for: deleted)
        #expect(a != b)
    }
}

//
//  WorkoutFinishingTests.swift
//  MCPStrengthTests
//
//  Covers discarding unticked sets when a workout is finished.
//
//  This is the only operation in the app that HARD-deletes user rows, so the
//  tests are about the boundary as much as the behaviour: exactly what goes,
//  exactly what stays, and that the thing which goes is really gone rather than
//  tombstoned — because storing a tombstone would defeat the reason for
//  discarding at all.
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct WorkoutFinishingTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, TemplateFolder.self, Template.self,
            TemplateExercise.self, TemplateSet.self, ProgramDay.self,
            Workout.self, WorkoutExercise.self, WorkoutSet.self,
            MeasurementType.self, MeasurementEntry.self,
            AppSettings.self,
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    /// One exercise, with the given (weight, reps, completed) sets.
    @discardableResult
    private func addExercise(
        _ name: String,
        to workout: Workout,
        in context: ModelContext,
        order: Int,
        sets: [(Double?, Int?, Bool)]
    ) -> WorkoutExercise {
        let exercise = Exercise(name: name, bodyPart: .chest,
                                category: .barbell, focusMetric: .totalVolume)
        context.insert(exercise)
        let we = WorkoutExercise(order: order, workout: workout, exercise: exercise)
        context.insert(we)
        for (i, s) in sets.enumerated() {
            context.insert(WorkoutSet(order: i, weight: s.0, reps: s.1,
                                      isCompleted: s.2, workoutExercise: we))
        }
        return we
    }

    // MARK: - What goes and what stays

    @Test func untickedSetsAreDiscardedAndTickedOnesSurvive() throws {
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        let we = addExercise("Bench Press", to: workout, in: context, order: 0,
                             sets: [(135, 8, true), (135, 6, true), (135, 5, false)])
        try context.save()
        #expect(we.liveSets.count == 3, "fixture wrong; the assertion below would prove nothing")

        WorkoutFinishing.finish(workout, elapsedSeconds: 600, in: context)

        #expect(we.liveSets.count == 2)
        #expect(we.liveSets.allSatisfy { $0.isCompleted })
    }

    @Test func discardedSetsAreReallyGoneNotTombstoned() throws {
        // The point of discarding is to NOT store rows describing training that
        // did not happen. A tombstone stores the row and, once sync lands,
        // uploads it — which is the opposite of the decision.
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        addExercise("Bench Press", to: workout, in: context, order: 0,
                    sets: [(135, 8, true), (135, 5, false)])
        try context.save()
        #expect(try context.fetch(FetchDescriptor<WorkoutSet>()).count == 2)

        WorkoutFinishing.finish(workout, elapsedSeconds: 600, in: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<WorkoutSet>())
        #expect(remaining.count == 1, "the unticked set is still in the store")
        #expect(remaining.allSatisfy { !$0.isTombstoned })
    }

    @Test func anExerciseWithNothingCompletedIsRemoved() throws {
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        addExercise("Bench Press", to: workout, in: context, order: 0,
                    sets: [(135, 8, true)])
        addExercise("Crunch", to: workout, in: context, order: 1,
                    sets: [(nil, 20, false), (nil, 15, false)])
        try context.save()
        #expect(workout.liveExercises.count == 2)

        WorkoutFinishing.finish(workout, elapsedSeconds: 600, in: context)

        #expect(workout.liveExercises.count == 1)
        #expect(workout.liveExercises.first?.exercise?.name == "Bench Press")
    }

    @Test func anExerciseKeepingOneSetSurvives() throws {
        // The line between "you did not do this exercise" and "you did some of
        // it". One completed set is doing it.
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        let we = addExercise("Bench Press", to: workout, in: context, order: 0,
                             sets: [(135, 8, false), (135, 6, true), (135, 5, false)])
        try context.save()

        WorkoutFinishing.finish(workout, elapsedSeconds: 600, in: context)

        #expect(workout.liveExercises.count == 1)
        #expect(we.liveSets.count == 1)
        #expect(we.liveSets.first?.reps == 6)
    }

    @Test func aWorkoutWhereNothingWasCompletedEmptiesOutRatherThanCrashing() throws {
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        addExercise("Bench Press", to: workout, in: context, order: 0,
                    sets: [(135, 8, false)])
        try context.save()

        WorkoutFinishing.finish(workout, elapsedSeconds: 600, in: context)

        #expect(workout.liveExercises.isEmpty)
        #expect(workout.totalVolume == 0)
        #expect(workout.completedAt != nil, "it still counts as a finished session")
    }

    // MARK: - Totals

    @Test func volumeIsComputedAfterTheDiscardNotBefore() throws {
        // Computing first would leave a total describing a workout that no
        // longer exists — the 0 lb confusion in reverse.
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        addExercise("Bench Press", to: workout, in: context, order: 0,
                    sets: [(100, 5, true), (999, 99, false)])
        try context.save()

        WorkoutFinishing.finish(workout, elapsedSeconds: 600, in: context)

        #expect(workout.totalVolume == 500, "the discarded set leaked into the total")
    }

    @Test func finishingMarksTheWorkoutForSync() throws {
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        addExercise("Bench Press", to: workout, in: context, order: 0, sets: [(100, 5, true)])
        workout.markSynced()
        #expect(workout.needsSync == false, "fixture wrong; the assertion below is vacuous")

        WorkoutFinishing.finish(workout, elapsedSeconds: 600, in: context)

        #expect(workout.needsSync, "a finished workout that is not dirty never uploads")
    }

    // MARK: - The summary that drives the confirmation

    @Test func summaryCountsWhatWouldBeLost() throws {
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        addExercise("Bench Press", to: workout, in: context, order: 0,
                    sets: [(135, 8, true), (135, 5, false)])
        addExercise("Crunch", to: workout, in: context, order: 1,
                    sets: [(nil, 20, false), (nil, 15, false)])
        try context.save()

        let summary = WorkoutFinishing.discardSummary(for: workout)

        #expect(summary.setCount == 3)
        #expect(summary.exerciseCount == 1, "only Crunch loses everything")
        #expect(!summary.isEmpty)
    }

    @Test func summaryIsEmptyWhenEverythingWasCompleted() throws {
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        addExercise("Bench Press", to: workout, in: context, order: 0,
                    sets: [(135, 8, true), (135, 6, true)])
        try context.save()

        #expect(WorkoutFinishing.discardSummary(for: workout).isEmpty)
    }

    @Test func onlyTypedInValuesCountAsWorthAskingAbout() throws {
        // An untouched set from a template is not worth interrupting someone
        // over; one they typed 135 x 6 into and forgot to tick is.
        let context = try makeContext()
        let blank = Workout(name: "Blank")
        context.insert(blank)
        addExercise("Bench Press", to: blank, in: context, order: 0, sets: [(nil, nil, false)])

        let typed = Workout(name: "Typed")
        context.insert(typed)
        addExercise("Bench Press", to: typed, in: context, order: 0, sets: [(135, 6, false)])
        try context.save()

        #expect(WorkoutFinishing.discardSummary(for: blank).hasEnteredValues == false)
        #expect(WorkoutFinishing.discardSummary(for: typed).hasEnteredValues == true)
    }

    @Test func inspectingChangesNothing() throws {
        // discardSummary runs on every Finish tap, before the user has agreed
        // to anything. If it mutated, tapping Finish and cancelling would
        // already have destroyed the sets.
        let context = try makeContext()
        let workout = Workout(name: "Push A")
        context.insert(workout)
        let we = addExercise("Bench Press", to: workout, in: context, order: 0,
                             sets: [(135, 8, true), (135, 5, false)])
        try context.save()

        _ = WorkoutFinishing.discardSummary(for: workout)

        #expect(we.liveSets.count == 2)
        #expect(workout.completedAt == nil)
        #expect(try context.fetch(FetchDescriptor<WorkoutSet>()).count == 2)
    }
}

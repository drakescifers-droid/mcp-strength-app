//
//  WorkoutHistoryTests.swift
//  MCPStrengthTests
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct WorkoutHistoryTests {

    private func makeContainer() throws -> ModelContext {
        let schema = Schema([
            Exercise.self,
            TemplateFolder.self,
            Template.self,
            TemplateExercise.self,
            TemplateSet.self,
            ProgramDay.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            MeasurementType.self,
            MeasurementEntry.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeExercise(in context: ModelContext, name: String = "Back Squat") -> Exercise {
        let exercise = Exercise(
            name: name,
            bodyPart: .legs,
            category: .barbell,
            focusMetric: .totalVolume
        )
        context.insert(exercise)
        return exercise
    }

    // MARK: - Total volume

    // (a) totalVolume sums weight × reps over COMPLETED sets only, ignoring
    // unchecked sets.
    @Test func totalVolumeSumsCompletedSetsOnly() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let workout = Workout(name: "Leg Day", startedAt: Date(), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(we)

        // Completed: 135 × 5 = 675
        context.insert(WorkoutSet(order: 0, weight: 135, reps: 5, isCompleted: true, completedAt: Date(), workoutExercise: we))
        // Completed: 185 × 5 = 925
        context.insert(WorkoutSet(order: 1, weight: 185, reps: 5, isCompleted: true, completedAt: Date(), workoutExercise: we))
        // Unchecked — must NOT count (would add 225 × 5 = 1125 if wrongly included)
        context.insert(WorkoutSet(order: 2, weight: 225, reps: 5, isCompleted: false, workoutExercise: we))

        let volume = WorkoutStats.totalVolume(for: workout)
        // 675 + 925 = 1600, not 2725
        #expect(volume == 1600)
    }

    // (b) totalVolume is zero for a workout with no completed sets — not nil,
    // not a crash.
    @Test func totalVolumeIsZeroWhenNoCompletedSets() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let workout = Workout(name: "Empty Workout", startedAt: Date(), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(we)

        context.insert(WorkoutSet(order: 0, weight: 135, reps: 5, isCompleted: false, workoutExercise: we))
        context.insert(WorkoutSet(order: 1, weight: 185, reps: 5, isCompleted: false, workoutExercise: we))

        let volume = WorkoutStats.totalVolume(for: workout)
        #expect(volume == 0)
    }

    // (c) totalVolume skips sets with nil weight or nil reps
    @Test func totalVolumeSkipsSetsWithMissingWeightOrReps() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let workout = Workout(name: "Partial Data", startedAt: Date(), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(we)

        // Completed with both values: 100 × 10 = 1000
        context.insert(WorkoutSet(order: 0, weight: 100, reps: 10, isCompleted: true, completedAt: Date(), workoutExercise: we))
        // Completed but missing weight — skip
        context.insert(WorkoutSet(order: 1, weight: nil, reps: 8, isCompleted: true, completedAt: Date(), workoutExercise: we))
        // Completed but missing reps — skip
        context.insert(WorkoutSet(order: 2, weight: 200, reps: nil, isCompleted: true, completedAt: Date(), workoutExercise: we))

        let volume = WorkoutStats.totalVolume(for: workout)
        #expect(volume == 1000)
    }

    // MARK: - Best set

    // (d) bestSet picks the highest weight × reps, not merely the heaviest
    // weight. A lighter-but-higher-rep set wins.
    @Test func bestSetPicksHighestVolumeNotHeaviestWeight() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let workout = Workout(name: "Test", startedAt: Date(), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(we)

        // Heavier weight, fewer reps: 300 × 2 = 600
        context.insert(WorkoutSet(order: 0, weight: 300, reps: 2, isCompleted: true, completedAt: Date(), workoutExercise: we))
        // Lighter weight, more reps: 135 × 10 = 1350 ← this should win
        context.insert(WorkoutSet(order: 1, weight: 135, reps: 10, isCompleted: true, completedAt: Date(), workoutExercise: we))

        let best = WorkoutStats.bestSet(for: we)
        #expect(best != nil)
        #expect(best?.weight == 135)
        #expect(best?.reps == 10)
    }

    // (e) bestSet breaks ties toward the heavier weight
    @Test func bestSetBreaksTiesTowardHeavierWeight() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let workout = Workout(name: "Test", startedAt: Date(), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(we)

        // Same volume: 200 × 5 = 1000
        context.insert(WorkoutSet(order: 0, weight: 200, reps: 5, isCompleted: true, completedAt: Date(), workoutExercise: we))
        // Same volume: 250 × 4 = 1000 — heavier, should win tie
        context.insert(WorkoutSet(order: 1, weight: 250, reps: 4, isCompleted: true, completedAt: Date(), workoutExercise: we))

        let best = WorkoutStats.bestSet(for: we)
        #expect(best != nil)
        #expect(best?.weight == 250)
        #expect(best?.reps == 4)
    }

    // (f) bestSet returns nil when there are no completed sets
    @Test func bestSetReturnsNilWhenNoCompletedSets() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let workout = Workout(name: "Test", startedAt: Date(), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(we)

        context.insert(WorkoutSet(order: 0, weight: 135, reps: 5, isCompleted: false, workoutExercise: we))
        context.insert(WorkoutSet(order: 1, weight: 185, reps: 5, isCompleted: false, workoutExercise: we))

        let best = WorkoutStats.bestSet(for: we)
        #expect(best == nil)
    }

    // (g) bestSet ignores completed sets missing weight or reps
    @Test func bestSetIgnoresSetsWithMissingWeightOrReps() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let workout = Workout(name: "Test", startedAt: Date(), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(we)

        // Completed but missing weight — ignore
        context.insert(WorkoutSet(order: 0, weight: nil, reps: 10, isCompleted: true, completedAt: Date(), workoutExercise: we))
        // Completed but missing reps — ignore
        context.insert(WorkoutSet(order: 1, weight: 500, reps: nil, isCompleted: true, completedAt: Date(), workoutExercise: we))
        // The real best: 225 × 5 = 1125
        context.insert(WorkoutSet(order: 2, weight: 225, reps: 5, isCompleted: true, completedAt: Date(), workoutExercise: we))

        let best = WorkoutStats.bestSet(for: we)
        #expect(best != nil)
        #expect(best?.weight == 225)
        #expect(best?.reps == 5)
    }

    // MARK: - History filtering / ordering

    // (h) An in-progress workout (completedAt == nil) is EXCLUDED from history.
    @Test func inProgressWorkoutIsExcludedFromHistory() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        // Completed workout
        let completed = Workout(name: "Done", startedAt: Date(timeIntervalSinceNow: -86400))
        completed.completedAt = Date(timeIntervalSinceNow: -86400)
        context.insert(completed)
        addExercise(to: completed, exercise: exercise, in: context)

        // In-progress workout — completedAt is nil
        let inProgress = Workout(name: "In Progress", startedAt: Date())
        context.insert(inProgress)
        let we = WorkoutExercise(order: 0, workout: inProgress, exercise: exercise)
        context.insert(we)
        context.insert(WorkoutSet(order: 0, weight: 225, reps: 5, isCompleted: true, completedAt: Date(), workoutExercise: we))

        let allWorkouts = try context.fetch(FetchDescriptor<Workout>())
        let history = WorkoutStats.completedWorkouts(from: allWorkouts)

        #expect(history.count == 1)
        #expect(history.first?.id == completed.id)
    }

    // (i) Workouts are ordered newest first
    @Test func workoutsOrderedNewestFirst() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let oldest = Workout(name: "Oldest", startedAt: Date(timeIntervalSinceNow: -86400 * 10))
        oldest.completedAt = Date(timeIntervalSinceNow: -86400 * 10)
        context.insert(oldest)
        addExercise(to: oldest, exercise: exercise, in: context)

        let middle = Workout(name: "Middle", startedAt: Date(timeIntervalSinceNow: -86400 * 5))
        middle.completedAt = Date(timeIntervalSinceNow: -86400 * 5)
        context.insert(middle)
        addExercise(to: middle, exercise: exercise, in: context)

        let newest = Workout(name: "Newest", startedAt: Date(timeIntervalSinceNow: -86400))
        newest.completedAt = Date(timeIntervalSinceNow: -86400)
        context.insert(newest)
        addExercise(to: newest, exercise: exercise, in: context)

        let allWorkouts = try context.fetch(FetchDescriptor<Workout>())
        let history = WorkoutStats.completedWorkouts(from: allWorkouts)

        #expect(history.count == 3)
        #expect(history[0].id == newest.id)
        #expect(history[1].id == middle.id)
        #expect(history[2].id == oldest.id)
    }

    // MARK: - Previous set type + PreviousText suffixes

    // previousSet copies the located set's setType, not just weight/reps —
    // otherwise a drop set and a working set at the same load are identical.
    @Test func previousSetCopiesSetTypeFromLocatedSet() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let completed = Workout(name: "Done", startedAt: Date(timeIntervalSinceNow: -86400))
        completed.completedAt = Date(timeIntervalSinceNow: -86400)
        context.insert(completed)
        let we = WorkoutExercise(order: 0, workout: completed, exercise: exercise)
        context.insert(we)
        context.insert(WorkoutSet(
            order: 0,
            setType: .dropSet,
            weight: 75,
            reps: 11,
            isCompleted: true,
            completedAt: completed.completedAt!,
            workoutExercise: we
        ))

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let prev = WorkoutHistory.previousSet(for: exercise, at: 0, in: workouts)
        #expect(prev?.weight == 75)
        #expect(prev?.reps == 11)
        #expect(prev?.setType == .dropSet)
    }

    // MARK: - A warm-up ramp does not shift the Previous column
    //
    // The load-bearing case. `Add Warm-up Sets` inserts three rows at the top
    // of the list, and Previous used to match last time's sets to today's rows
    // by RAW LIST POSITION. So generating a ramp shifted everything down a
    // slot: the previous working load was drawn against a 45 lb warm-up and the
    // working set read "—". Found by looking at the running app; no assertion
    // here could see it, because both halves were internally consistent and
    // simply pointed at the wrong row.
    //
    // Warm-ups now count in their own sequence rather than being dropped: the
    // reference app shows previous warm-up loads on warm-up rows, tagged (W).

    private func makeHistory(
        _ context: ModelContext,
        for exercise: Exercise,
        sets: [(Int, SetType, Double, Int)]
    ) throws -> [Workout] {
        let completed = Workout(name: "Done", startedAt: Date(timeIntervalSinceNow: -86400))
        completed.completedAt = Date(timeIntervalSinceNow: -86400)
        context.insert(completed)
        let we = WorkoutExercise(order: 0, workout: completed, exercise: exercise)
        context.insert(we)
        for (order, type, weight, reps) in sets {
            context.insert(WorkoutSet(
                order: order,
                setType: type,
                weight: weight,
                reps: reps,
                isCompleted: true,
                completedAt: completed.completedAt!,
                workoutExercise: we
            ))
        }
        return try context.fetch(FetchDescriptor<Workout>())
    }

    // History side. Position 0 of the WORKING sequence is the first working
    // set, not the first warm-up — a ramp logged last time must not shift it.
    @Test func previousSetCountsWorkingSetsPastAnyWarmups() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)
        let workouts = try makeHistory(context, for: exercise, sets: [
            (0, .warmup, 45, 5),
            (1, .warmup, 55, 5),
            (2, .normal, 135, 5),
            (3, .normal, 145, 3),
        ])

        #expect(WorkoutHistory.previousSet(for: exercise, at: 0, in: workouts)?.weight == 135)
        #expect(WorkoutHistory.previousSet(for: exercise, at: 1, in: workouts)?.weight == 145)
        // Only two working sets existed, so there is no third.
        #expect(WorkoutHistory.previousSet(for: exercise, at: 2, in: workouts) == nil)
    }

    // A warm-up row reads last time's WARM-UPS, in their own sequence, and
    // carries the type through so PreviousText can tag it (W).
    @Test func previousSetMatchesWarmupsToWarmups() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)
        let workouts = try makeHistory(context, for: exercise, sets: [
            (0, .warmup, 45, 5),
            (1, .warmup, 55, 5),
            (2, .normal, 135, 5),
        ])

        let first = WorkoutHistory.previousSet(for: exercise, at: 0, like: .warmup, in: workouts)
        #expect(first?.weight == 45)
        #expect(first?.setType == .warmup)
        #expect(PreviousText.format(first) == "45 lb × 5 (W)")

        #expect(WorkoutHistory.previousSet(for: exercise, at: 1, like: .warmup, in: workouts)?.weight == 55)
        // Two warm-ups last time; a third warm-up today has nothing to show.
        #expect(WorkoutHistory.previousSet(for: exercise, at: 2, like: .warmup, in: workouts) == nil)
    }

    // A drop set counts as working, not as a warm-up: it is a real performance
    // at that point in the sequence.
    @Test func previousSetTreatsDropSetsAsPartOfTheWorkingSequence() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)
        let workouts = try makeHistory(context, for: exercise, sets: [
            (0, .warmup, 45, 5),
            (1, .normal, 135, 5),
            (2, .dropSet, 75, 11),
        ])

        let second = WorkoutHistory.previousSet(for: exercise, at: 1, like: .dropSet, in: workouts)
        #expect(second?.weight == 75)
        #expect(second?.setType == .dropSet)
    }

    // Display side: the positions a caller feeds in. Each kind counts itself.
    @Test func previousPositionsCountEachKindSeparately() {
        #expect(
            SetNumbering.positionsWithinKind(for: [.warmup, .warmup, .warmup, .normal])
            == [0, 1, 2, 0]
        )
        #expect(
            SetNumbering.positionsWithinKind(for: [.warmup, .normal, .dropSet, .failure])
            == [0, 0, 1, 2]
        )
        // Adding a ramp above the working sets must not move them.
        #expect(SetNumbering.positionsWithinKind(for: [.normal, .normal]) == [0, 1])
        #expect(
            SetNumbering.positionsWithinKind(for: [.warmup, .warmup, .warmup, .normal, .normal])
            == [0, 1, 2, 0, 1]
        )
        #expect(SetNumbering.positionsWithinKind(for: []) == [])
    }

    // The two rules are deliberately different and must not be collapsed into
    // one: numbering skips every lettered type and returns nil for it,
    // Previous skips nothing and counts warm-ups in their own sequence.
    @Test func numberingAndPreviousPositionsDisagreeOnDropSets() {
        let types: [SetType] = [.warmup, .normal, .dropSet, .normal]
        #expect(SetNumbering.workingNumbers(for: types) == [nil, 1, nil, 2])
        #expect(SetNumbering.positionsWithinKind(for: types) == [0, 0, 1, 2])
    }

    // Lettered types get a suffix after the load; `.normal` does not.
    @Test func previousTextAppendsSuffixForLetteredTypesOnly() {
        #expect(PreviousText.format(.init(weight: 135, reps: 8, setType: .warmup)) == "135 lb × 8 (W)")
        #expect(PreviousText.format(.init(weight: 75, reps: 11, setType: .dropSet)) == "75 lb × 11 (D)")
        #expect(PreviousText.format(.init(weight: 225, reps: 5, setType: .failure)) == "225 lb × 5 (F)")
        #expect(PreviousText.format(.init(weight: 225, reps: 5, setType: .normal)) == "225 lb × 5")
        #expect(PreviousText.format(.init(weight: 225, reps: 5)) == "225 lb × 5")
    }

    // No prior set, and a prior set with a type but no load, both stay "—".
    // A bare "(D)" would look like data where there is none.
    @Test func previousTextKeepsEmDashWhenThereIsNoLoad() {
        #expect(PreviousText.format(nil) == "—")
        #expect(PreviousText.format(.init(weight: nil, reps: nil, setType: .dropSet)) == "—")
        #expect(PreviousText.format(.init(weight: nil, reps: nil, setType: .warmup)) == "—")
        #expect(PreviousText.format(.init(weight: nil, reps: nil, setType: .failure)) == "—")
        #expect(PreviousText.format(.init(weight: nil, reps: nil, setType: .normal)) == "—")
    }

    // MARK: - Helpers

    @discardableResult
    private func addExercise(to workout: Workout, exercise: Exercise, in context: ModelContext) -> WorkoutExercise {
        let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(we)
        context.insert(WorkoutSet(order: 0, weight: 135, reps: 5, isCompleted: true, completedAt: Date(), workoutExercise: we))
        return we
    }
}

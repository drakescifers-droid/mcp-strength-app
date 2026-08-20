//
//  ActiveWorkoutTests.swift
//  MCPStrengthTests
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct ActiveWorkoutTests {

    private func makeContainer() throws -> ModelContext {
        let schema = Schema([
            Exercise.self,
            ExercisePreference.self,
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
            AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeExercise(in context: ModelContext, name: String = "Back Squat") -> Exercise {
        let exercise = Exercise(
            name: name,
            bodyPart: .legs,
            category: .barbell
        )
        context.insert(exercise)
        return exercise
    }

    // (a) Adding an exercise to a workout creates one WorkoutExercise with one set.
    @Test func addingExerciseAppendsOneExerciseWithOneSet() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)
        let workout = Workout(name: "Afternoon Workout", startedAt: Date())
        context.insert(workout)

        addExercise(to: workout, exercise: exercise, in: context)

        let fetchedExercises = try context.fetch(FetchDescriptor<WorkoutExercise>())
        let fetchedSets = try context.fetch(FetchDescriptor<WorkoutSet>())

        #expect(fetchedExercises.count == 1)
        #expect(fetchedExercises.first?.exercise?.id == exercise.id)
        #expect(fetchedExercises.first?.workout?.id == workout.id)

        #expect(fetchedSets.count == 1)
        #expect(fetchedSets.first?.workoutExercise?.id == fetchedExercises.first?.id)
        #expect(fetchedSets.first?.order == 0)
        #expect(fetchedSets.first?.setType == .normal)
    }

    // (b) Adding a set appends with the right order and default setType .normal.
    @Test func addingSetAppendsWithRightOrderAndNormalType() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)
        let workout = Workout(name: "Afternoon Workout", startedAt: Date())
        context.insert(workout)
        let we = addExercise(to: workout, exercise: exercise, in: context)

        addSet(to: we, restSeconds: 90, in: context)
        addSet(to: we, restSeconds: 120, in: context)

        let fetched = try context.fetch(FetchDescriptor<WorkoutSet>())
        #expect(fetched.count == 3)
        let sorted = fetched.sorted { $0.order < $1.order }
        #expect(sorted.map(\.order) == [0, 1, 2])
        #expect(sorted.allSatisfy { $0.setType == .normal })
    }

    // (c) Toggling isCompleted sets and clears completedAt.
    @Test func togglingCompletionSetsAndClearsCompletedAt() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)
        let workout = Workout(name: "Afternoon Workout", startedAt: Date())
        context.insert(workout)
        let we = addExercise(to: workout, exercise: exercise, in: context)

        let set = we.sets.first!
        #expect(set.isCompleted == false)
        #expect(set.completedAt == nil)

        set.isCompleted = true
        set.completedAt = Date()
        #expect(set.isCompleted == true)
        #expect(set.completedAt != nil)

        set.isCompleted = false
        set.completedAt = nil
        #expect(set.isCompleted == false)
        #expect(set.completedAt == nil)
    }

    // (d) PREVIOUS returns the matching set from the most recent COMPLETED
    // workout, ignores the in-progress one, and returns nil when there is no
    // history.
    @Test func previousSetFindsMostRecentCompletedIgnoringInProgress() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        // --- Older completed workout (set position 0 = 135 x 5). ---
        let older = Workout(name: "Old Workout", startedAt: Date(timeIntervalSinceNow: -86400 * 7))
        older.completedAt = Date(timeIntervalSinceNow: -86400 * 7)
        context.insert(older)
        let olderWE = WorkoutExercise(order: 0, workout: older, exercise: exercise)
        context.insert(olderWE)
        context.insert(WorkoutSet(order: 0, weight: 135, reps: 5, isCompleted: true, completedAt: older.completedAt!, workoutExercise: olderWE))

        // --- More recent completed workout (set position 0 = 185 x 5). ---
        let recent = Workout(name: "Recent Workout", startedAt: Date(timeIntervalSinceNow: -86400))
        recent.completedAt = Date(timeIntervalSinceNow: -86400)
        context.insert(recent)
        let recentWE = WorkoutExercise(order: 0, workout: recent, exercise: exercise)
        context.insert(recentWE)
        context.insert(WorkoutSet(order: 0, weight: 185, reps: 5, isCompleted: true, completedAt: recent.completedAt!, workoutExercise: recentWE))

        // --- In-progress workout with a logged set at position 0 — must be ignored. ---
        let inProgress = Workout(name: "Afternoon Workout", startedAt: Date())
        context.insert(inProgress)
        let inProgressWE = WorkoutExercise(order: 0, workout: inProgress, exercise: exercise)
        context.insert(inProgressWE)
        context.insert(WorkoutSet(order: 0, weight: 225, reps: 3, workoutExercise: inProgressWE))

        let workouts = try context.fetch(FetchDescriptor<Workout>())

        let prev = WorkoutHistory.previousSet(
            for: exercise,
            at: 0,
            in: workouts,
            excluding: inProgress
        )
        #expect(prev != nil)
        #expect(prev?.weight == 185)
        #expect(prev?.reps == 5)
    }

    @Test func previousSetReturnsNilWhenNoHistory() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)
        let inProgress = Workout(name: "Afternoon Workout", startedAt: Date())
        context.insert(inProgress)
        let we = WorkoutExercise(order: 0, workout: inProgress, exercise: exercise)
        context.insert(we)
        context.insert(WorkoutSet(order: 0, weight: 225, reps: 5, workoutExercise: we))

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let prev = WorkoutHistory.previousSet(
            for: exercise,
            at: 0,
            in: workouts,
            excluding: inProgress
        )
        #expect(prev == nil)
    }

    @Test func previousSetIgnoresIncompleteWorkoutsEvenWithoutExplicitExclusion() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        // An uncompleted workout exists (completedAt == nil) — must not count.
        let uncompleted = Workout(name: "Forgotten Workout", startedAt: Date(timeIntervalSinceNow: -86400))
        context.insert(uncompleted)
        let we = WorkoutExercise(order: 0, workout: uncompleted, exercise: exercise)
        context.insert(we)
        context.insert(WorkoutSet(order: 0, weight: 315, reps: 1, isCompleted: true, completedAt: Date(), workoutExercise: we))

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let prev = WorkoutHistory.previousSet(for: exercise, at: 0, in: workouts)
        #expect(prev == nil)
    }

    // MARK: - PreviousText formatting

    // Weights here are STORED KILOGRAMS, written as the pounds they represent
    // so the expected strings stay readable. That is the whole shape of the
    // change: the same lift, the same string, and a completely different
    // number in the column.
    @Test func previousTextFormatsWeightAndReps() {
        func kg(_ pounds: Double) -> Double {
            WeightUnits.kilograms(from: pounds, in: .lbs)
        }
        #expect(PreviousText.format(nil, in: .lbs) == "—")
        #expect(PreviousText.format(.init(weight: kg(85), reps: 5), in: .lbs) == "85 lb × 5")
        #expect(PreviousText.format(.init(weight: kg(82.5), reps: 8), in: .lbs) == "82.5 lb × 8")
        // A set recorded with no values still reads as em dash, not " lb × ".
        #expect(PreviousText.format(.init(weight: nil, reps: nil), in: .lbs) == "—")
        #expect(PreviousText.format(.init(weight: kg(100), reps: nil), in: .lbs) == "100 lb")
        #expect(PreviousText.format(.init(weight: nil, reps: 12), in: .lbs) == "× 12")
    }

    // The same stored numbers read to a metric lifter. Nothing about the row
    // changes except the two facts the unit decides.
    @Test func previousTextRendersTheSameStoredWeightInKilograms() {
        // 100 kg stored, which is what a metric lifter typed.
        #expect(PreviousText.format(.init(weight: 100, reps: 5), in: .kg) == "100 kg × 5")
        // 135 lb stored is 61.23496995 kg, shown to two decimals.
        let benchInKilograms = WeightUnits.kilograms(from: 135, in: .lbs)
        #expect(PreviousText.format(.init(weight: benchInKilograms, reps: 5), in: .kg)
                == "61.23 kg × 5")
        #expect(PreviousText.format(.init(weight: benchInKilograms, reps: 5), in: .lbs)
                == "135 lb × 5")
    }

    // A drop set keeps its letter in both units — the suffix is about the set
    // type and must not be disturbed by the unit label sitting next to it.
    @Test func theSetTypeLetterSurvivesTheUnitLabel() {
        #expect(PreviousText.format(.init(weight: 60, reps: 8, setType: .dropSet), in: .kg)
                == "60 kg × 8 (D)")
        #expect(PreviousText.format(.init(weight: 60, reps: 8, setType: .restPause), in: .kg)
                == "60 kg × 8 (R)")
        #expect(PreviousText.format(.init(weight: nil, reps: nil, setType: .warmup), in: .kg)
                == "—", "no load recorded must not render a lone (W)")
    }

    // The formatter has to absorb the float noise a conversion round trip
    // leaves behind, because `String(Double)` does not. 135 lb stored is
    // 61.23496995 kg, and rounding that to two decimals lands on
    // 61.230000000000004 — 0.01 has no exact binary form. That reached the
    // screen verbatim before the formatter counted in hundredths.
    @Test func formatWeightDoesNotLeakFloatNoise() {
        let bench = WeightUnits.displayed(
            from: WeightUnits.kilograms(from: 135, in: .lbs),
            in: .kg
        )
        #expect(bench != 61.23, "precondition: the rounded value is not exactly 61.23")
        #expect(PreviousText.formatWeight(bench) == "61.23")

        // Every 2.5 lb step from an empty bar to a heavy deadlift, read in
        // kilograms. None may render more than two decimals.
        for pounds in stride(from: 2.5, through: 600, by: 2.5) {
            let text = PreviousText.formatWeight(
                WeightUnits.displayed(from: WeightUnits.kilograms(from: pounds, in: .lbs), in: .kg)
            )
            let decimals = text.split(separator: ".").last.map { $0.count } ?? 0
            #expect(text.contains(".") ? decimals <= 2 : true,
                    "\(pounds) lb rendered as \(text)")
        }
    }

    // Whole numbers lose the ".0", halves keep one decimal, and neither gains a
    // trailing zero. A session volume must not be truncated either.
    @Test func formatWeightKeepsTheShortestHonestForm() {
        #expect(PreviousText.formatWeight(135) == "135")
        #expect(PreviousText.formatWeight(82.5) == "82.5")
        #expect(PreviousText.formatWeight(61.23) == "61.23")
        #expect(PreviousText.formatWeight(0) == "0")
        #expect(PreviousText.formatWeight(12345.67) == "12345.67")
    }

    // MARK: - Helpers mirroring the screen's mutation logic

    @discardableResult
    private func addExercise(to workout: Workout, exercise: Exercise, in context: ModelContext) -> WorkoutExercise {
        let nextOrder = (workout.exercises.map(\.order).max() ?? -1) + 1
        let we = WorkoutExercise(order: nextOrder, workout: workout, exercise: exercise)
        context.insert(we)
        let firstSet = WorkoutSet(order: 0)
        firstSet.workoutExercise = we
        context.insert(firstSet)
        return we
    }

    @discardableResult
    private func addSet(to workoutExercise: WorkoutExercise, restSeconds: Int, in context: ModelContext) -> WorkoutSet {
        let nextOrder = (workoutExercise.sets.map(\.order).max() ?? -1) + 1
        let set = WorkoutSet(order: nextOrder, restSeconds: restSeconds, workoutExercise: workoutExercise)
        context.insert(set)
        return set
    }
}

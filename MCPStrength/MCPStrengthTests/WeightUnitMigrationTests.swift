//
//  WeightUnitMigrationTests.swift
//  MCPStrengthTests
//
//  The one-shot conversion of stored pounds to canonical kilograms.
//
//  There is exactly one thing here that is worth being afraid of, and it is not
//  the arithmetic: **running twice**. A second pass multiplies kilograms by
//  0.45359237 again and halves every lift ever logged, silently, into plausible
//  numbers. So the guard tests below matter more than the conversion tests, and
//  `runningTwiceDoesNotConvertTwice` is the load-bearing one in this file.
//
//  What these tests cannot check is the real store. They build an in-memory
//  container from the CURRENT schema, so there is never a pounds-era store to
//  open — the same limitation `AppSettingsTests` records. What they DO pin is
//  that the guard exists, that it survives a fresh context, and that the marker
//  and the rows are written together.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct WeightUnitMigrationTests {

    /// A real (in-memory) container, kept so several contexts can be opened
    /// against the SAME store — which is what "the marker lives in the store"
    /// actually has to mean, and what a single shared context would not prove.
    private func makeContainer() throws -> ModelContainer {
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
            AppSettings.self,
            StoreMigrations.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A workout with one exercise and the given pound loads, plus the stored
    /// volume Finish would have computed from them.
    @discardableResult
    private func makePoundsWorkout(
        in context: ModelContext,
        weights: [Double?],
        reps: Int = 5
    ) -> Workout {
        let exercise = Exercise(
            name: "Bench Press (Barbell)",
            bodyPart: .chest,
            category: .barbell,
            focusMetric: .totalVolume
        )
        context.insert(exercise)

        let workout = Workout(name: "Push", startedAt: .now, completedAt: .now)
        context.insert(workout)

        let block = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
        context.insert(block)

        for (index, weight) in weights.enumerated() {
            context.insert(WorkoutSet(
                order: index,
                weight: weight,
                reps: reps,
                isCompleted: true,
                completedAt: .now,
                workoutExercise: block
            ))
        }
        workout.totalVolume = WorkoutStats.totalVolume(for: workout)
        return workout
    }

    // MARK: - The conversion

    @Test func poundsBecomeKilograms() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        makePoundsWorkout(in: context, weights: [135, 185])

        let outcome = try WeightUnitMigration.run(in: context)
        #expect(outcome == .converted(workoutSets: 2, templateSets: 0, workouts: 1))

        let sets = try context.fetch(FetchDescriptor<WorkoutSet>()).sorted { $0.order < $1.order }
        #expect(sets[0].weight == 135 * WeightUnits.kilogramsPerPound)
        #expect(sets[1].weight == 185 * WeightUnits.kilogramsPerPound)

        // And they read back as what was typed. This is the assertion that
        // matters to a person: the screens divide by the same constant, so a
        // converted store still says 135.
        #expect(WeightUnits.displayed(from: sets[0].weight!, in: .lbs) == 135)
    }

    // The one that hides. `totalVolume` is a stored, synced `weight × reps`
    // total that nothing recomputes on read, and no property in it is called
    // "weight". Convert the sets without it and every history card reports 2.2×
    // the sets printed underneath it.
    @Test func theStoredWorkoutVolumeIsConvertedWithItsSets() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = makePoundsWorkout(in: context, weights: [100], reps: 10)
        #expect(workout.totalVolume == 1000, "precondition: 100 lb × 10")

        try WeightUnitMigration.run(in: context)

        #expect(workout.totalVolume == 1000 * WeightUnits.kilogramsPerPound)

        // The header and the set list have to agree: the volume must still be
        // the sum of the sets under it, recomputed from the converted rows.
        #expect(abs(workout.totalVolume - WorkoutStats.totalVolume(for: workout)) < 0.000001)
    }

    @Test func templateSetsAreConvertedToo() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let exercise = Exercise(
            name: "Back Squat (Barbell)",
            bodyPart: .legs,
            category: .barbell,
            focusMetric: .totalVolume
        )
        context.insert(exercise)
        let template = Template(name: "Leg Day", order: 0)
        context.insert(template)
        let block = TemplateExercise(order: 0, template: template, exercise: exercise)
        context.insert(block)
        context.insert(TemplateSet(order: 0, weight: 225, reps: 5, templateExercise: block))
        // A prescription with only a rep range and no weight — very common, and
        // it must not be counted or touched.
        context.insert(TemplateSet(order: 1, repRangeStart: 6, repRangeEnd: 8, templateExercise: block))

        let outcome = try WeightUnitMigration.run(in: context)
        #expect(outcome == .converted(workoutSets: 0, templateSets: 1, workouts: 0))

        let sets = try context.fetch(FetchDescriptor<TemplateSet>()).sorted { $0.order < $1.order }
        #expect(sets[0].weight == 225 * WeightUnits.kilogramsPerPound)
        #expect(sets[1].weight == nil, "no weight is absence, not zero")
    }

    // A bodyweight set carries no weight. `nil` must stay `nil` rather than
    // becoming 0 — a fabricated zero here would put "0 kg × 8" on a pull-up.
    @Test func setsWithNoWeightAreLeftAlone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        makePoundsWorkout(in: context, weights: [nil, nil, nil])

        let outcome = try WeightUnitMigration.run(in: context)
        #expect(outcome == .converted(workoutSets: 0, templateSets: 0, workouts: 0))
        #expect(try context.fetch(FetchDescriptor<WorkoutSet>()).allSatisfy { $0.weight == nil })
    }

    // Tombstoned rows are converted as well. They are invisible on every screen
    // but they are still rows the server has, and a store where the live
    // weights are kilograms and the deleted ones are pounds has two meanings
    // for one column.
    @Test func tombstonedRowsAreConvertedAsWell() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        makePoundsWorkout(in: context, weights: [135, 185])

        let sets = try context.fetch(FetchDescriptor<WorkoutSet>()).sorted { $0.order < $1.order }
        sets[1].markDeleted()

        try WeightUnitMigration.run(in: context)
        #expect(sets[1].weight == 185 * WeightUnits.kilogramsPerPound)
    }

    // MARK: - The guard

    // THE LOAD-BEARING TEST IN THIS FILE. A second pass would convert
    // kilograms as if they were pounds and halve everything, and the result
    // looks like a real training log, so nothing downstream would notice.
    @Test func runningTwiceDoesNotConvertTwice() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        makePoundsWorkout(in: context, weights: [315])

        try WeightUnitMigration.run(in: context)
        let afterFirst = try context.fetch(FetchDescriptor<WorkoutSet>())[0].weight

        let second = try WeightUnitMigration.run(in: context)
        #expect(second == .alreadyConverted)
        #expect(try context.fetch(FetchDescriptor<WorkoutSet>())[0].weight == afterFirst)

        // Spelled out, because this is the number the failure would produce:
        // 315 lb is 142.88 kg, and a second pass would make it 64.8.
        #expect(WeightUnits.displayed(from: afterFirst!, in: .lbs) == 315)
    }

    // The marker has to survive a fresh context, because that is the only thing
    // it is for: the app opens a new one on every launch. A guard that lived in
    // memory would pass the test above and convert again tomorrow.
    @Test func theMarkerSurvivesANewContextOnTheSameStore() throws {
        let container = try makeContainer()

        let first = ModelContext(container)
        makePoundsWorkout(in: first, weights: [225])
        try WeightUnitMigration.run(in: first)

        let second = ModelContext(container)
        #expect(try WeightUnitMigration.run(in: second) == .alreadyConverted)

        let sets = try second.fetch(FetchDescriptor<WorkoutSet>())
        #expect(WeightUnits.displayed(from: sets[0].weight!, in: .lbs) == 225)
    }

    // An empty store still records that it ran. Without this a fresh install
    // stays marked unconverted forever, and the first workout ever logged —
    // already in kilograms — gets converted on the next launch.
    @Test func anEmptyStoreIsStillMarkedConverted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        #expect(try WeightUnitMigration.run(in: context)
                == .converted(workoutSets: 0, templateSets: 0, workouts: 0))
        #expect(try WeightUnitMigration.run(in: context) == .alreadyConverted)
    }

    // MARK: - What it must not do

    // Converting is not a user edit. Marking rows dirty here would push
    // kilograms at a server that converts its own rows in the same release, and
    // would dirty an entire history for a change that produces identical values
    // on both ends. See the file comment on WeightUnitMigration.
    @Test func conversionDoesNotMarkRowsAsNeedingSync() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = makePoundsWorkout(in: context, weights: [135])

        // Pretend everything has already been pushed and confirmed.
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        for set in sets { set.markSynced() }
        workout.markSynced()

        try WeightUnitMigration.run(in: context)

        #expect(sets.allSatisfy { !$0.needsSync })
        #expect(!workout.needsSync)
    }

    // The marker is not a setting and must never travel to another device: a
    // second device that pulled `true` would skip its own conversion. Keeping
    // it off `Syncable` is what makes that structural rather than a comment.
    @Test func theMarkerIsNotSyncable() {
        #expect(!(StoreMigrations.self is any Syncable.Type))
    }
}

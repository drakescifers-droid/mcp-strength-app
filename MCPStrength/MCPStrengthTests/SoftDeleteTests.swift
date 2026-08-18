//
//  SoftDeleteTests.swift
//  MCPStrengthTests
//
//  Covers the manual cascade and the `live…` accessors.
//
//  These matter because SwiftData's `@Relationship(deleteRule:)` no longer runs
//  for a delete — every rule the models declare is now performed by hand in
//  SoftDelete.swift, and nothing but a test connects the two. A cascade that
//  stops one level short leaves rows that are live on the server, belong to a
//  deleted parent, and get pulled back down by every other device.
//
//  The nullify cases are the ones worth reading twice. They assert that
//  something was NOT touched, which is a weaker kind of test — so each one
//  first asserts the delete actually happened, or it would pass just as well
//  against a function that did nothing at all.
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct SoftDeleteTests {

    // MARK: - Fixture

    /// A template with two exercises of two sets each, a folder, a program day,
    /// and a workout performed from the template.
    private struct Fixture {
        let context: ModelContext
        let folder: TemplateFolder
        let template: Template
        let exerciseA: TemplateExercise
        let exerciseB: TemplateExercise
        let setsA: [TemplateSet]
        let day: ProgramDay
        let workout: Workout
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema([
            Exercise.self, TemplateFolder.self, Template.self,
            TemplateExercise.self, TemplateSet.self, ProgramDay.self,
            Workout.self, WorkoutExercise.self, WorkoutSet.self,
            MeasurementType.self, MeasurementEntry.self,
            AppSettings.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let folder = TemplateFolder(name: "Q2 2026", order: 0)
        let template = Template(name: "Push A", order: 0, folder: folder)
        context.insert(folder)
        context.insert(template)

        var setsA: [TemplateSet] = []
        var exercises: [TemplateExercise] = []
        for i in 0..<2 {
            let tx = TemplateExercise(order: i, template: template)
            context.insert(tx)
            exercises.append(tx)
            for j in 0..<2 {
                let ts = TemplateSet(order: j, reps: 5, templateExercise: tx)
                context.insert(ts)
                if i == 0 { setsA.append(ts) }
            }
        }

        let day = ProgramDay(order: 0, folder: folder, template: template)
        context.insert(day)

        let workout = Workout(name: "Push A", template: template)
        context.insert(workout)

        try context.save()
        return Fixture(context: context, folder: folder, template: template,
                       exerciseA: exercises[0], exerciseB: exercises[1],
                       setsA: setsA, day: day, workout: workout)
    }

    // MARK: - Template cascade

    @Test func deletingATemplateCascadesToExercisesAndSets() throws {
        let f = try makeFixture()
        #expect(f.template.isTombstoned == false)
        #expect(f.exerciseA.isTombstoned == false)
        #expect(f.setsA.allSatisfy { !$0.isTombstoned })

        SoftDelete.template(f.template)

        #expect(f.template.isTombstoned)
        #expect(f.exerciseA.isTombstoned)
        #expect(f.exerciseB.isTombstoned)
        #expect(f.setsA.allSatisfy { $0.isTombstoned }, "sets were left live under a deleted template")
    }

    @Test func deletingATemplateNeverTouchesTheWorkoutsPerformedFromIt() throws {
        // The single most important delete rule in the app. A cascade that
        // reached workouts would destroy training history on every device.
        let f = try makeFixture()
        SoftDelete.template(f.template)

        #expect(f.template.isTombstoned, "the delete did not happen, so this proves nothing")
        #expect(f.workout.isTombstoned == false)
        #expect(f.workout.name == "Push A", "the workout lost its copied name")
    }

    @Test func everythingCascadedIsMarkedForSync() throws {
        // A tombstone that never gets pushed is invisible to every other
        // device, which is the same as not deleting it at all.
        let f = try makeFixture()
        f.template.markSynced()
        f.exerciseA.markSynced()
        f.setsA.forEach { $0.markSynced() }
        #expect(f.template.needsSync == false)

        SoftDelete.template(f.template)

        #expect(f.template.needsSync)
        #expect(f.exerciseA.needsSync)
        #expect(f.setsA.allSatisfy { $0.needsSync })
    }

    // MARK: - Folder cascade

    @Test func deletingAFolderKeepsItsTemplatesAndCascadesToProgramDays() throws {
        let f = try makeFixture()

        SoftDelete.folder(f.folder)

        #expect(f.folder.isTombstoned, "the delete did not happen, so this proves nothing")
        #expect(f.day.isTombstoned, "program days should go with their folder")
        #expect(f.template.isTombstoned == false, "deleting a folder deleted its templates")
    }

    @Test func aTemplateInADeletedFolderReadsAsUnfiledRatherThanVanishing() throws {
        let f = try makeFixture()
        SoftDelete.folder(f.folder)

        // It survives, and the folder it points at is a tombstone — which is
        // how nullify is emulated. The UI filters folders by deletedAt, so the
        // template shows up in the unfiled list.
        #expect(f.template.isTombstoned == false)
        #expect(f.template.folder?.isTombstoned == true)
    }

    // MARK: - Workout cascade

    @Test func deletingAWorkoutCascadesToItsExercisesAndSets() throws {
        let f = try makeFixture()
        let we = WorkoutExercise(order: 0, workout: f.workout)
        f.context.insert(we)
        let ws = WorkoutSet(order: 0, weight: 100, reps: 5, workoutExercise: we)
        f.context.insert(ws)
        try f.context.save()

        SoftDelete.workout(f.workout)

        #expect(f.workout.isTombstoned)
        #expect(we.isTombstoned)
        #expect(ws.isTombstoned)
    }

    // MARK: - The live accessors

    @Test func liveAccessorsHideTombstonesAndKeepOrder() throws {
        let f = try makeFixture()
        #expect(f.template.liveExercises.count == 2)

        SoftDelete.templateExercise(f.exerciseA)

        let live = f.template.liveExercises
        #expect(live.count == 1)
        #expect(live.first?.id == f.exerciseB.id)
        // The raw relationship still has both — sync needs the tombstone.
        #expect(f.template.exercises.count == 2)
    }

    @Test func liveSetsHideTombstonedSets() throws {
        let f = try makeFixture()
        #expect(f.exerciseA.liveSets.count == 2)

        f.setsA[0].markDeleted()

        #expect(f.exerciseA.liveSets.count == 1)
        #expect(f.exerciseA.sets.count == 2)
    }

    @Test func liveAccessorsSortByOrder() throws {
        let f = try makeFixture()
        // Insertion order is not a guarantee SwiftData makes, so the accessor
        // sorting is what every call site now relies on instead of doing it
        // itself.
        let orders = f.template.liveExercises.map(\.order)
        #expect(orders == orders.sorted())
    }

    @Test func liveTemplatesHidesDeletedTemplates() throws {
        let f = try makeFixture()
        #expect(f.folder.liveTemplates.count == 1)

        SoftDelete.template(f.template)

        #expect(f.folder.liveTemplates.isEmpty)
    }

    // MARK: - Downstream readers

    @Test func totalVolumeIgnoresDeletedSets() throws {
        // A deleted set that still counted would keep inflating a workout's
        // volume after removal — a number the user cannot explain or correct.
        let f = try makeFixture()
        let we = WorkoutExercise(order: 0, workout: f.workout)
        f.context.insert(we)
        let kept = WorkoutSet(order: 0, weight: 100, reps: 5, isCompleted: true, workoutExercise: we)
        let removed = WorkoutSet(order: 1, weight: 200, reps: 5, isCompleted: true, workoutExercise: we)
        f.context.insert(kept)
        f.context.insert(removed)
        try f.context.save()

        #expect(WorkoutStats.totalVolume(for: f.workout) == 1500)

        removed.markDeleted()

        #expect(WorkoutStats.totalVolume(for: f.workout) == 500)
    }

    @Test func bestSetIgnoresDeletedSets() throws {
        let f = try makeFixture()
        let we = WorkoutExercise(order: 0, workout: f.workout)
        f.context.insert(we)
        let light = WorkoutSet(order: 0, weight: 100, reps: 5, isCompleted: true, workoutExercise: we)
        let heavy = WorkoutSet(order: 1, weight: 225, reps: 5, isCompleted: true, workoutExercise: we)
        f.context.insert(light)
        f.context.insert(heavy)
        try f.context.save()

        #expect(WorkoutStats.bestSet(for: we)?.weight == 225)

        heavy.markDeleted()

        #expect(WorkoutStats.bestSet(for: we)?.weight == 100)
    }

    @Test func startingFromATemplateSkipsDeletedExercises() throws {
        // Otherwise a deleted exercise reappears in every workout started from
        // that template — a deletion that looks like it did not take.
        let f = try makeFixture()
        SoftDelete.templateExercise(f.exerciseA)

        let workout = TemplateStarter.start(
            from: f.template, at: Date(), in: f.context
        )

        #expect(workout.exercises.count == 1)
    }

    @Test func previousSetIgnoresDeletedHistory() throws {
        // The Previous column is a claim about what you actually lifted. A
        // deleted set answering it is a fabricated number.
        let f = try makeFixture()
        let exercise = Exercise(
            name: "Bench Press", bodyPart: .chest, category: .barbell, focusMetric: .totalVolume
        )
        f.context.insert(exercise)

        let past = Workout(name: "Old", startedAt: .now.addingTimeInterval(-86_400))
        past.completedAt = .now.addingTimeInterval(-80_000)
        f.context.insert(past)
        let pastExercise = WorkoutExercise(order: 0, workout: past, exercise: exercise)
        f.context.insert(pastExercise)
        let pastSet = WorkoutSet(order: 0, weight: 185, reps: 5, isCompleted: true,
                                 workoutExercise: pastExercise)
        f.context.insert(pastSet)
        try f.context.save()

        #expect(
            WorkoutHistory.previousSet(for: exercise, at: 0, in: [past])?.weight == 185,
            "the fixture is wrong, so the deletion assertion below would prove nothing"
        )

        pastSet.markDeleted()

        #expect(WorkoutHistory.previousSet(for: exercise, at: 0, in: [past]) == nil)
    }
}

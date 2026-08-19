//
//  TemplateTests.swift
//  MCPStrengthTests
//
//  Covers the template→workout path and the naming rule from
//  docs/01-data-model.md § Workouts (corrected once already): a workout started
//  from a template takes the TEMPLATE's name, copied onto Workout.name at
//  start and never read through the relationship; a quick workout with no
//  template gets a generated time-of-day name.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct TemplateTests {

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

    // (a) Creating a template with exercises and sets persists them.
    @Test func creatingTemplatePersistsExercisesAndSets() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let template = Template(name: "Leg Day", order: 0)
        context.insert(template)

        let tx = TemplateExercise(order: 0, defaultRestSeconds: 180, template: template, exercise: exercise)
        context.insert(tx)
        context.insert(TemplateSet(order: 0, setType: .normal, weight: 225, reps: 5, restSeconds: 180, templateExercise: tx))
        context.insert(TemplateSet(order: 1, setType: .warmup, weight: 135, reps: 8, restSeconds: 120, templateExercise: tx))

        try context.save()

        let fetchedTemplates = try context.fetch(FetchDescriptor<Template>())
        let fetched = try #require(fetchedTemplates.first { $0.id == template.id })

        let ex = try #require(fetched.exercises.first)
        #expect(ex.exercise?.name == "Back Squat")
        #expect(ex.defaultRestSeconds == 180)

        let sets = ex.sets.sorted { $0.order < $1.order }
        #expect(sets.count == 2)
        #expect(sets[0].weight == 225)
        #expect(sets[0].reps == 5)
        #expect(sets[0].setType == .normal)
        #expect(sets[0].restSeconds == 180)
        #expect(sets[1].setType == .warmup)
    }

    // (b) Starting a workout from a template copies the right number of
    // exercises and sets, with isCompleted false on every set.
    @Test func startingWorkoutFromTemplateCopiesExercisesAndSets() throws {
        let context = try makeContainer()
        let squat = makeExercise(in: context, name: "Back Squat")
        let bench = Exercise(name: "Bench Press", bodyPart: .chest, category: .barbell)
        context.insert(bench)

        let template = Template(name: "Full Body", order: 0)
        context.insert(template)

        let txA = TemplateExercise(order: 0, defaultRestSeconds: 180, template: template, exercise: squat)
        let txB = TemplateExercise(order: 1, defaultRestSeconds: 120, template: template, exercise: bench)
        context.insert(txA)
        context.insert(txB)
        context.insert(TemplateSet(order: 0, setType: .normal, weight: 225, reps: 5, restSeconds: 180, templateExercise: txA))
        context.insert(TemplateSet(order: 1, setType: .normal, weight: 245, reps: 3, restSeconds: 180, templateExercise: txA))
        context.insert(TemplateSet(order: 0, setType: .normal, weight: 185, reps: 8, restSeconds: 120, templateExercise: txB))
        try context.save()

        let workout = TemplateStarter.start(from: template, in: context)
        try context.save()

        let fetchedWorkouts = try context.fetch(FetchDescriptor<Workout>())
        let started = try #require(fetchedWorkouts.first { $0.id == workout.id })

        let exercises = started.exercises.sorted { $0.order < $1.order }
        #expect(exercises.count == 2)
        #expect(exercises[0].exercise?.name == "Back Squat")
        #expect(exercises[1].exercise?.name == "Bench Press")

        let squatSets = exercises[0].sets.sorted { $0.order < $1.order }
        let benchSets = exercises[1].sets.sorted { $0.order < $1.order }
        #expect(squatSets.count == 2)
        #expect(benchSets.count == 1)

        // Copied starting values.
        #expect(squatSets[0].weight == 225)
        #expect(squatSets[0].reps == 5)
        #expect(squatSets[0].setType == .normal)
        #expect(squatSets[0].restSeconds == 180)
        // Every copied set starts incomplete.
        #expect(squatSets.allSatisfy { $0.isCompleted == false })
        #expect(benchSets.allSatisfy { $0.isCompleted == false })
        #expect(started.exercises.flatMap(\.sets).allSatisfy { $0.isCompleted == false })
    }

    // (c) The started workout's name equals the template's name — explicitly.
    @Test func startedWorkoutNameEqualsTemplateName() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let template = Template(name: "Push Day", order: 0)
        context.insert(template)
        let tx = TemplateExercise(order: 0, template: template, exercise: exercise)
        context.insert(tx)
        context.insert(TemplateSet(order: 0, weight: 135, reps: 5, restSeconds: 90, templateExercise: tx))
        try context.save()

        let workout = TemplateStarter.start(from: template, in: context)

        #expect(workout.name == "Push Day")
        #expect(workout.name == template.name)
        #expect(workout.template?.id == template.id)
    }

    // (d) Renaming the template AFTER starting a workout does NOT change the
    // already-started workout's name — the name is copied, not read through.
    @Test func renamingTemplateAfterStartDoesNotChangeWorkoutName() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let template = Template(name: "Leg Day", order: 0)
        context.insert(template)
        let tx = TemplateExercise(order: 0, template: template, exercise: exercise)
        context.insert(tx)
        context.insert(TemplateSet(order: 0, weight: 225, reps: 5, restSeconds: 90, templateExercise: tx))
        try context.save()

        let workout = TemplateStarter.start(from: template, in: context)
        try context.save()
        let workoutID = workout.id

        // Rename the template after the workout was started.
        template.name = "Lower Body"

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        let started = try #require(fetched.first { $0.id == workoutID })

        #expect(started.name == "Leg Day")
        #expect(template.name == "Lower Body")
        #expect(started.name != template.name)
    }

    // (e) A quick workout with no template still gets a generated name, not an
    // empty one.
    @Test func quickWorkoutWithoutTemplateGetsGeneratedName() throws {
        let context = try makeContainer()

        // Mirror ContentView's no-template path: generate the name, persist it.
        let workout = Workout(name: WorkoutNaming.quickWorkoutName(for: Date()), startedAt: Date())
        context.insert(workout)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        let started = try #require(fetched.first { $0.id == workout.id })

        #expect(started.name.isEmpty == false)
        #expect(started.template == nil)
        #expect(started.name.hasSuffix("Workout"))
    }

    // (f) The generated time-of-day name picks the right part for a few hours.
    @Test func quickWorkoutNameReflectsTimeOfDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)

        components.hour = 8
        #expect(WorkoutNaming.quickWorkoutName(for: calendar.date(from: components)!, calendar: calendar) == "Morning Workout")

        components.hour = 14
        #expect(WorkoutNaming.quickWorkoutName(for: calendar.date(from: components)!, calendar: calendar) == "Afternoon Workout")

        components.hour = 19
        #expect(WorkoutNaming.quickWorkoutName(for: calendar.date(from: components)!, calendar: calendar) == "Evening Workout")

        components.hour = 2
        #expect(WorkoutNaming.quickWorkoutName(for: calendar.date(from: components)!, calendar: calendar) == "Night Workout")
    }

    // (g) Deleting a template does not affect a workout already started from it
    // (the name was copied; the relationship is nullable). The workout survives
    // with its copied name intact.
    @Test func deletingTemplateAfterStartLeavesWorkoutIntact() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let template = Template(name: "Pull Day", order: 0)
        context.insert(template)
        let tx = TemplateExercise(order: 0, template: template, exercise: exercise)
        context.insert(tx)
        context.insert(TemplateSet(order: 0, weight: 135, reps: 5, restSeconds: 90, templateExercise: tx))
        try context.save()

        let workout = TemplateStarter.start(from: template, in: context)
        try context.save()
        let workoutID = workout.id

        context.delete(template)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())

        // The dangerous failure mode is a CASCADE: if deleting a template took its
        // performed workouts with it, tidying up your templates would silently
        // destroy training history. Assert the workout survives at all, first.
        let started = try #require(
            fetched.first { $0.id == workoutID },
            "deleting a template must not delete workouts already performed from it"
        )

        // The documented contract (docs/01 § Workouts): name is a stored copy, so it
        // survives the template being renamed or deleted.
        #expect(started.name == "Pull Day")

        // Template.workouts now declares `.nullify` with an explicit inverse, so the
        // dangling reference is gone: the workout survives and its link goes nil.
        #expect(started.template == nil)
    }
}

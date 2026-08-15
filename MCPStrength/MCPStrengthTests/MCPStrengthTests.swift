//
//  MCPStrengthTests.swift
//  MCPStrengthTests
//
//  Created by Drake Scifers on 8/14/26.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct MCPStrengthTests {

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

    // (a) Exercise insert/fetch with aliases round-trip
    @Test func exercisePersistsAndRoundTripsAliases() throws {
        let context = try makeContainer()
        let exercise = Exercise(
            name: "Chest Fly (Machine)",
            aliases: ["pec deck", "machine fly"],
            bodyPart: .chest,
            category: .machineOther,
            isCustom: true,
            weightUnitOverride: .lbs,
            focusMetric: .totalVolume,
            notes: "Squeeze at the top"
        )
        context.insert(exercise)
        try context.save()

        let id = exercise.id
        let fetched = try context.fetch(FetchDescriptor<Exercise>())
        let found = try #require(fetched.first { $0.id == id })

        #expect(found.name == "Chest Fly (Machine)")
        #expect(found.aliases == ["pec deck", "machine fly"])
        #expect(found.aliases.count == 2)
        #expect(found.bodyPart == .chest)
        #expect(found.category == .machineOther)
        #expect(found.isCustom == true)
        #expect(found.weightUnitOverride == .lbs)
        #expect(found.focusMetric == .totalVolume)
        #expect(found.notes == "Squeeze at the top")
        #expect(found.barType == nil)
    }

    // (b) Template -> TemplateExercise -> TemplateSet relationship resolves
    @Test func templateRelationshipResolvesThroughSets() throws {
        let context = try makeContainer()
        let exercise = Exercise(
            name: "Back Squat",
            bodyPart: .legs,
            category: .barbell,
            focusMetric: .totalVolume
        )
        context.insert(exercise)

        let template = Template(name: "Leg Day", order: 0)
        context.insert(template)

        let templateExercise = TemplateExercise(order: 0, defaultRestSeconds: 180)
        templateExercise.template = template
        templateExercise.exercise = exercise
        context.insert(templateExercise)

        let set = TemplateSet(order: 0, weight: 225, reps: 5, restSeconds: 180)
        set.templateExercise = templateExercise
        context.insert(set)

        try context.save()

        let fetchedTemplates = try context.fetch(FetchDescriptor<Template>())
        let fetched = try #require(fetchedTemplates.first { $0.id == template.id })

        let ex = try #require(fetched.exercises.first)
        #expect(ex.exercise?.name == "Back Squat")
        #expect(ex.defaultRestSeconds == 180)

        let fetchedSet = try #require(ex.sets.first)
        #expect(fetchedSet.weight == 225)
        #expect(fetchedSet.reps == 5)
        #expect(fetchedSet.templateExercise?.id == ex.id)
    }

    // (c) TemplateSet carries rep range + rpe
    @Test func templateSetPersistsRepRangeAndRPE() throws {
        let context = try makeContainer()
        let template = Template(name: "Hypertrophy", order: 0)
        context.insert(template)

        let templateExercise = TemplateExercise(order: 0, defaultRestSeconds: 120)
        templateExercise.template = template
        context.insert(templateExercise)

        let set = TemplateSet(
            order: 0,
            setType: .normal,
            repRangeStart: 6,
            repRangeEnd: 8,
            rpe: 8.5,
            restSeconds: 120
        )
        set.templateExercise = templateExercise
        context.insert(set)

        try context.save()

        let fetchedSets = try context.fetch(FetchDescriptor<TemplateSet>())
        let found = try #require(fetchedSets.first { $0.id == set.id })

        #expect(found.repRangeStart == 6)
        #expect(found.repRangeEnd == 8)
        #expect(found.rpe == 8.5)
        #expect(found.reps == nil)
        #expect(found.setType == .normal)
    }

    // (d) Program folder with ordered ProgramDay list, same template twice
    @Test func programDayListPreservesOrderAndRepetition() throws {
        let context = try makeContainer()

        let folder = TemplateFolder(name: "A/B Split", order: 0, kind: .program, cursor: 0, totalCycles: nil)
        context.insert(folder)

        let templateA = Template(name: "Workout A", order: 0, folder: folder)
        let templateB = Template(name: "Workout B", order: 1, folder: folder)
        context.insert(templateA)
        context.insert(templateB)

        // A, B, A — same template appears twice
        let day0 = ProgramDay(order: 0, label: "Day 1", folder: folder, template: templateA)
        let day1 = ProgramDay(order: 1, label: "Day 2", folder: folder, template: templateB)
        let day2 = ProgramDay(order: 2, label: "Day 3", folder: folder, template: templateA)
        context.insert(day0)
        context.insert(day1)
        context.insert(day2)

        try context.save()

        var descriptor = FetchDescriptor<ProgramDay>()
        descriptor.sortBy = [SortDescriptor(\.order)]
        let days = try context.fetch(descriptor)

        #expect(days.count == 3)
        #expect(days[0].template?.name == "Workout A")
        #expect(days[1].template?.name == "Workout B")
        #expect(days[2].template?.name == "Workout A")
        #expect(days[0].template?.id == days[2].template?.id)
        #expect(folder.kind == .program)
        #expect(folder.cursor == 0)
        #expect(folder.totalCycles == nil)
    }

    // Bonus: WorkoutSet must NOT carry rep range, but DOES carry rpe + completion
    @Test func workoutSetHasNoRepRangeButCarriesRPEAndCompletion() throws {
        let context = try makeContainer()
        let exercise = Exercise(name: "Bench Press", bodyPart: .chest, category: .barbell, focusMetric: .totalVolume)
        context.insert(exercise)

        let workout = Workout(name: "Afternoon Workout", startedAt: Date(), durationSeconds: 3600)
        context.insert(workout)

        let workoutExercise = WorkoutExercise(order: 0)
        workoutExercise.workout = workout
        workoutExercise.exercise = exercise
        context.insert(workoutExercise)

        let set = WorkoutSet(order: 0, weight: 185, reps: 8, rpe: 9, restSeconds: 150, isCompleted: true, completedAt: Date())
        set.workoutExercise = workoutExercise
        context.insert(set)

        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkoutSet>())
        let found = try #require(fetched.first { $0.id == set.id })

        #expect(found.weight == 185)
        #expect(found.reps == 8)
        #expect(found.rpe == 9)
        #expect(found.isCompleted == true)
        #expect(found.completedAt != nil)
    }

    // Bonus: MeasurementEntry source distinguishes manual vs HealthKit
    @Test func measurementEntryDistinguishesSource() throws {
        let context = try makeContainer()
        let weightType = MeasurementType(name: "Weight", group: .core)
        context.insert(weightType)

        let manual = MeasurementEntry(value: 195.4, unit: "lb", source: .manual, type: weightType)
        let healthKit = MeasurementEntry(value: 195.1, unit: "lb", source: .healthKit, type: weightType)
        context.insert(manual)
        context.insert(healthKit)

        try context.save()

        let entries = try context.fetch(FetchDescriptor<MeasurementEntry>())
        #expect(entries.count == 2)
        let hk = try #require(entries.first { $0.source == .healthKit })
        let man = try #require(entries.first { $0.source == .manual })
        #expect(hk.value == 195.1)
        #expect(man.value == 195.4)
        #expect(hk.type?.name == "Weight")
    }
}

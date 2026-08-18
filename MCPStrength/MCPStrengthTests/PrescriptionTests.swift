//
//  PrescriptionTests.swift
//  MCPStrengthTests
//
//  Covers RPE validation and starting a workout from a template that carries a
//  rep range (the rule: pre-fill reps with the bottom of the range).
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct PrescriptionTests {

    // MARK: - RPE validation

    @Test func rpeAcceptsListedHalfSteps() {
        for value in RPE.allowedValues {
            #expect(RPE.isValid(value), "RPE \(value) should be valid")
        }
    }

    @Test func rpeRejects5_5() {
        #expect(RPE.isValid(5.5) == false)
    }

    @Test func rpeRejects10_5() {
        #expect(RPE.isValid(10.5) == false)
    }

    @Test func rpeRejects8_25() {
        #expect(RPE.isValid(8.25) == false)
    }

    @Test func rpeFormatsWholeAndHalf() {
        #expect(RPE.format(8) == "8")
        #expect(RPE.format(8.5) == "8.5")
        #expect(RPE.format(10) == "10")
    }

    // MARK: - TemplateStarter: range pre-fills reps with repRangeStart

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
            AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func startingFromRangeTemplatePreFillsRepsWithStart() throws {
        let context = try makeContainer()
        let exercise = Exercise(
            name: "Back Squat",
            bodyPart: .legs,
            category: .barbell,
            focusMetric: .totalVolume
        )
        context.insert(exercise)

        let template = Template(name: "Hypertrophy", order: 0)
        context.insert(template)
        let tx = TemplateExercise(order: 0, defaultRestSeconds: 120, template: template, exercise: exercise)
        context.insert(tx)
        // A range prescription: 6-8, RPE 8. No fixed `reps`.
        context.insert(TemplateSet(
            order: 0,
            setType: .normal,
            weight: 185,
            repRangeStart: 6,
            repRangeEnd: 8,
            rpe: 8,
            restSeconds: 120,
            templateExercise: tx
        ))
        try context.save()

        let workout = TemplateStarter.start(from: template, in: context)
        try context.save()

        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let started = try #require(sets.first { $0.workoutExercise?.workout?.id == workout.id })

        // Pre-filled with the BOTTOM of the range — where a lifter starts before
        // adjusting up.
        #expect(started.reps == 6)
        // RPE (prescribed effort) is copied across as the target.
        #expect(started.rpe == 8)
    }

    @Test func startingFromFixedRepsTemplateCopiesRepsUnchanged() throws {
        let context = try makeContainer()
        let exercise = Exercise(
            name: "Bench Press",
            bodyPart: .chest,
            category: .barbell,
            focusMetric: .totalVolume
        )
        context.insert(exercise)

        let template = Template(name: "Strength", order: 0)
        context.insert(template)
        let tx = TemplateExercise(order: 0, defaultRestSeconds: 180, template: template, exercise: exercise)
        context.insert(tx)
        context.insert(TemplateSet(
            order: 0,
            setType: .normal,
            weight: 225,
            reps: 5,
            rpe: 9,
            restSeconds: 180,
            templateExercise: tx
        ))
        try context.save()

        let workout = TemplateStarter.start(from: template, in: context)
        try context.save()

        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let started = try #require(sets.first { $0.workoutExercise?.workout?.id == workout.id })

        // Fixed reps copied unchanged; rpe copied across.
        #expect(started.reps == 5)
        #expect(started.rpe == 9)
    }
}

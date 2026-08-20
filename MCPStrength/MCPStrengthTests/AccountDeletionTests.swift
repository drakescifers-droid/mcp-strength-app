//
//  AccountDeletionTests.swift
//  MCPStrengthTests
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct AccountDeletionTests {

    @Test func wipeTombsUserWorkAndKeepsTheLibrary() throws {
        let schema = Schema([
            Exercise.self, ExercisePreference.self, TemplateFolder.self, Template.self,
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

        let library = Exercise(name: "Bench Press", bodyPart: .chest, category: .barbell, isCustom: false)
        let custom = Exercise(name: "Drake Machine", bodyPart: .back, category: .machineOther, isCustom: true)
        context.insert(library)
        context.insert(custom)

        let folder = TemplateFolder(name: "Push", order: 0)
        let template = Template(name: "A", order: 0, folder: folder)
        context.insert(folder)
        context.insert(template)
        let tx = TemplateExercise(order: 0, template: template)
        context.insert(tx)
        context.insert(TemplateSet(order: 0, reps: 5, templateExercise: tx))

        let workout = Workout(name: "A", template: template)
        context.insert(workout)
        let we = WorkoutExercise(order: 0, workout: workout, exercise: library)
        context.insert(we)
        context.insert(WorkoutSet(order: 0, reps: 5, workoutExercise: we))

        let settings = AppSettings.current(in: context)
        try context.save()

        try AccountDeletion.wipeLocalUserData(in: context)

        #expect(library.deletedAt == nil)
        #expect(custom.deletedAt != nil)
        #expect(workout.deletedAt != nil)
        #expect(we.deletedAt != nil)
        #expect(template.deletedAt != nil)
        #expect(tx.deletedAt != nil)
        #expect(folder.deletedAt != nil)
        #expect(settings.deletedAt != nil)
    }

    @Test func presenterDoesNotUseAFabricatedOfflineGuessOnAServerError() {
        let message = AccountDeletionPresenter.message(
            for: AccountDeletionError.server(status: 500, body: "nope")
        )
        #expect(message.contains("server"))
        #expect(!message.lowercased().contains("network"))
    }
}

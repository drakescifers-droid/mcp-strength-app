//
//  ExercisePreferenceTests.swift
//  MCPStrengthTests
//
//  Pins the absences. A preference row existing where the user never set
//  one is the same shape as the 43 fabricated discard entries in
//  `00faec1`: a value meaning "never touched" being read as "the user
//  did something". The interesting cases here are the ones that must
//  NOT happen.
//
//  What these tests CANNOT check is the thing most likely to break the
//  app: a missing declaration-level default crashing `ModelContainer(for:)`
//  against an older store. In-memory containers are built from the CURRENT
//  schema, so there is never an old store to migrate. See docs/04-status.md.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct ExercisePreferenceTests {

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

    private func makeExercise(
        in context: ModelContext,
        name: String = "Bench Press (Barbell)"
    ) throws -> Exercise {
        let exercise = Exercise(
            name: name,
            bodyPart: .chest,
            category: .barbell
        )
        context.insert(exercise)
        try context.save()
        return exercise
    }

    // MARK: - Sparse by construction

    // The test most worth having. Inserting an exercise must not invent a
    // preference row. Reading is `exercise.preference?.<field>`; a row
    // exists only where the user set one.
    @Test func aFreshExerciseHasNoPreferenceRow() throws {
        let context = try makeContainer()
        let exercise = try makeExercise(in: context)

        #expect(exercise.preference == nil)
        #expect(try context.fetch(FetchDescriptor<ExercisePreference>()).isEmpty)
    }

    // MARK: - Resolution

    // Two devices setting a bar type for the same exercise must arrive at
    // the same row identity independently. The exercise's id is that
    // identity; a freshly minted UUID would make last-write-wins unable
    // to tell the two rows apart.
    @Test func resolvingCreatesARowWhoseIdEqualsTheExerciseId() throws {
        let context = try makeContainer()
        let exercise = try makeExercise(in: context)

        let preference = ExercisePreference.current(for: exercise, in: context)
        try context.save()

        #expect(preference.id == exercise.id)
        #expect(exercise.preference === preference)
        #expect(preference.exercise === exercise)
    }

    @Test func resolvingTwiceReturnsTheSameRow() throws {
        let context = try makeContainer()
        let exercise = try makeExercise(in: context)

        let first = ExercisePreference.current(for: exercise, in: context)
        try context.save()
        let second = ExercisePreference.current(for: exercise, in: context)

        #expect(first.id == second.id)
        #expect(first === second)
        #expect(try context.fetch(FetchDescriptor<ExercisePreference>()).count == 1)
    }

    // Creating the row is not itself an edit. Stamping `.now` here would
    // date a row of pure defaults before the user has set anything.
    @Test func resolvingDoesNotStampAnEdit() throws {
        let context = try makeContainer()
        let exercise = try makeExercise(in: context)

        let preference = ExercisePreference.current(for: exercise, in: context)
        #expect(preference.updatedAt == .distantPast)
        #expect(preference.needsSync == true)
    }

    // MARK: - Display unit

    @Test func displayUnitFollowsTheOverrideWhenTheUserHasSetOne() throws {
        let context = try makeContainer()
        let exercise = try makeExercise(in: context)
        let preference = ExercisePreference.current(for: exercise, in: context)
        preference.weightUnitOverride = .kg
        preference.markEdited()

        #expect(
            WeightUnits.displayUnit(
                override: exercise.preference?.weightUnitOverride,
                global: .lbs
            ) == .kg
        )
    }

    // Two different absences that must behave identically. A nil override
    // IS the *Default* option in the reference app's three-way Weight Unit
    // row, not a missing value to paper over.
    @Test func displayUnitFollowsTheGlobalInBothAbsentCases() throws {
        let context = try makeContainer()
        let exercise = try makeExercise(in: context)

        #expect(exercise.preference == nil, "no row at all")
        #expect(
            WeightUnits.displayUnit(
                override: exercise.preference?.weightUnitOverride,
                global: .kg
            ) == .kg
        )
        #expect(
            WeightUnits.displayUnit(
                override: exercise.preference?.weightUnitOverride,
                global: .lbs
            ) == .lbs
        )

        let preference = ExercisePreference.current(for: exercise, in: context)
        #expect(preference.weightUnitOverride == nil, "a row whose override is nil")
        #expect(
            WeightUnits.displayUnit(
                override: exercise.preference?.weightUnitOverride,
                global: .kg
            ) == .kg
        )
        #expect(
            WeightUnits.displayUnit(
                override: exercise.preference?.weightUnitOverride,
                global: .lbs
            ) == .lbs
        )
    }

    // MARK: - Declaration defaults

    @Test func syncColumnsLandOnTheirDeclarationDefaults() {
        let preference = ExercisePreference(id: UUID())

        #expect(preference.needsSync == true)
        #expect(preference.updatedAt == .distantPast)
        #expect(preference.deletedAt == nil)
        #expect(preference.focusMetric == .totalVolume)
        #expect(preference.weightUnitOverride == nil)
        #expect(preference.barType == nil)
        #expect(preference.notes == nil)
    }

    @Test func markEditedStampsAndDirties() {
        let preference = ExercisePreference(id: UUID())
        preference.needsSync = false
        #expect(preference.needsSync == false)

        let when = Date(timeIntervalSince1970: 1_800_000_000)
        preference.markEdited(at: when)

        #expect(preference.needsSync == true)
        #expect(preference.updatedAt == when)
    }
}

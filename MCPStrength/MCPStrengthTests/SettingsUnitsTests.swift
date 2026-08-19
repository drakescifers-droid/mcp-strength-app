//
//  SettingsUnitsTests.swift
//  MCPStrengthTests
//
//  The settings screen's one rule, and the vocabulary it shares with the
//  Preferences sheet.
//
//  Neither of these can be checked by looking at the screen. The no-op guard is
//  invisible — picking the unit that is already selected LOOKS identical either
//  way — and the shared label is only wrong when you have both screens open at
//  once, which nobody does while building one of them.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct SettingsUnitsTests {

    private func makeContext() throws -> ModelContext {
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
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    // MARK: - Writing the unit

    @Test func choosingADifferentUnitWritesItAndMarksTheRow() throws {
        let context = try makeContext()
        let settings = AppSettings.current(in: context)
        settings.needsSync = false
        settings.updatedAt = .distantPast

        settings.setWeightUnit(.kg)

        #expect(settings.weightUnit == .kg)
        #expect(settings.needsSync == true)
        #expect(settings.updatedAt > .distantPast)
    }

    // THE LOAD-BEARING ONE. Opening the picker, seeing which option has the
    // tick and tapping it is an ordinary thing to do, and it must not count as
    // an edit. A row that dirties itself every time somebody LOOKS at it would,
    // once this syncs, beat a genuine edit made on another device purely
    // because this device was opened more recently — and cost a push per glance.
    @Test func rePickingTheSameUnitDoesNotMarkTheRow() throws {
        let context = try makeContext()
        let settings = AppSettings.current(in: context)
        settings.weightUnit = .kg
        settings.needsSync = false
        settings.updatedAt = .distantPast

        settings.setWeightUnit(.kg)

        #expect(settings.weightUnit == .kg)
        #expect(settings.needsSync == false, "re-picking the current value is not an edit")
        #expect(settings.updatedAt == .distantPast, "updatedAt must not move")
    }

    @Test func switchingBackAndForthMarksEachRealChange() throws {
        let context = try makeContext()
        let settings = AppSettings.current(in: context)

        settings.setWeightUnit(.kg)
        #expect(settings.weightUnit == .kg)

        settings.needsSync = false
        settings.setWeightUnit(.lbs)
        #expect(settings.weightUnit == .lbs)
        #expect(settings.needsSync == true, "switching back is still a change")
    }

    // The screen writes through `current(in:)`, which must resolve to the one
    // row rather than making a second one per visit.
    @Test func writingThroughCurrentDoesNotCreateASecondRow() throws {
        let context = try makeContext()

        AppSettings.current(in: context).setWeightUnit(.kg)
        try context.save()
        AppSettings.current(in: context).setWeightUnit(.lbs)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<AppSettings>()).count == 1)
    }

    // MARK: - The workout calorie rate

    // Same rule as the unit, and the same reason it is on the model rather than
    // in the view: the guard is the interesting part and a view cannot be
    // tested.
    @Test func choosingADifferentCalorieRateWritesItAndMarksTheRow() throws {
        let context = try makeContext()
        let settings = AppSettings.current(in: context)
        settings.needsSync = false
        settings.updatedAt = .distantPast

        settings.setWorkoutCalorieRate(.high)

        #expect(settings.workoutCalorieRate == .high)
        #expect(settings.needsSync == true)
        #expect(settings.updatedAt > .distantPast)
    }

    @Test func rePickingTheSameCalorieRateDoesNotMarkTheRow() throws {
        let context = try makeContext()
        let settings = AppSettings.current(in: context)
        settings.needsSync = false
        settings.updatedAt = .distantPast

        settings.setWorkoutCalorieRate(.medium)

        #expect(settings.workoutCalorieRate == .medium)
        #expect(settings.needsSync == false, "re-picking the current value is not an edit")
        #expect(settings.updatedAt == .distantPast, "updatedAt must not move")
    }

    // CHOOSING `none` IS A REAL CHANGE, and it is the case a rule written as
    // "write it if there is something to write" silently drops — the same shape
    // as clearing a per-exercise preference back to Default. Turning energy off
    // has to travel, or the setting un-does itself on the next pull.
    @Test func turningTheRateOffIsAnEditLikeAnyOther() throws {
        let context = try makeContext()
        let settings = AppSettings.current(in: context)
        settings.setWorkoutCalorieRate(.veryHigh)
        settings.needsSync = false
        settings.updatedAt = .distantPast

        settings.setWorkoutCalorieRate(.none)

        #expect(settings.workoutCalorieRate == .none)
        #expect(settings.needsSync == true, "turning it off must travel")
    }

    // The client default has to be the SERVER's default. A device that has
    // never opened the picker must agree with the row the server hands its next
    // device, and `20260819180000_workout_calorie_rate.sql` says `default
    // 'medium'`.
    @Test func aFreshSettingsRowDefaultsToTheServersDefault() throws {
        let context = try makeContext()
        #expect(AppSettings.current(in: context).workoutCalorieRate == .medium)
    }

    // MARK: - The rate's labels

    // The row's value names the NUMBER it stands for, which is what makes a
    // user-chosen estimate honest rather than an unexplained assertion. The
    // wording is the reference app's own.
    @Test func theCalorieRateLabelCarriesItsNumber() {
        #expect(WorkoutCalorieRate.medium.settingsLabel == "Medium (200 kcal per hour)")
        #expect(WorkoutCalorieRate.veryHigh.settingsLabel == "Very High (300 kcal per hour)")
    }

    // And `none` carries no number, because "None (0 kcal per hour)" reads as a
    // measurement of zero rather than as "do not write energy at all" — the
    // fabricated zero, exactly.
    @Test func noneIsNamedWithoutAZero() {
        #expect(WorkoutCalorieRate.none.settingsLabel == "None")
        #expect(!WorkoutCalorieRate.none.settingsLabel.contains("0"))
    }

    // MARK: - The label both screens use

    // The settings row displays the value with the SAME string the picker
    // offered, and the Preferences sheet offers the same two again. Two screens
    // that choose one setting and name it differently read as two settings.
    @Test func settingsLabelsAreTheReferenceAppsWording() {
        #expect(WeightUnit.lbs.settingsLabel == "US/Imperial (lbs)")
        #expect(WeightUnit.kg.settingsLabel == "Metric (kg)")
    }

    // `settingsLabel` names a SYSTEM to somebody choosing between two of them;
    // `abbreviation` trails a number and `columnHeader` heads a column. They are
    // three different jobs and collapsing them is the tidy-up to resist —
    // "lb" alone does not say US/Imperial.
    @Test func theThreeUnitLabelsStayDistinct() {
        for unit in WeightUnit.allCases {
            #expect(unit.settingsLabel != unit.abbreviation)
            #expect(unit.settingsLabel != unit.columnHeader)
        }
    }

    // MARK: - What the global unit actually reaches

    // The whole point of the screen: with no per-exercise override, every
    // weight resolves through the global setting. This is the path that has
    // never been reachable before, because nothing could change the value.
    @Test func theGlobalUnitDrivesDisplayWhenNoOverrideIsSet() throws {
        let context = try makeContext()
        let settings = AppSettings.current(in: context)
        let exercise = Exercise(name: "Back Squat", bodyPart: .legs, category: .barbell)
        context.insert(exercise)

        settings.setWeightUnit(.kg)
        #expect(
            WeightUnits.displayUnit(
                override: exercise.preference?.weightUnitOverride,
                global: settings.weightUnit
            ) == .kg
        )

        settings.setWeightUnit(.lbs)
        #expect(
            WeightUnits.displayUnit(
                override: exercise.preference?.weightUnitOverride,
                global: settings.weightUnit
            ) == .lbs
        )
    }

    // And the per-exercise override still wins, so changing the global does not
    // quietly overrule an exercise somebody deliberately pinned to kilograms.
    @Test func aPerExerciseOverrideOutranksTheGlobal() throws {
        let context = try makeContext()
        let settings = AppSettings.current(in: context)
        let exercise = Exercise(name: "Back Squat", bodyPart: .legs, category: .barbell)
        context.insert(exercise)

        let preference = ExercisePreference.current(for: exercise, in: context)
        preference.weightUnitOverride = .kg
        preference.markEdited()
        settings.setWeightUnit(.lbs)

        #expect(
            WeightUnits.displayUnit(
                override: exercise.preference?.weightUnitOverride,
                global: settings.weightUnit
            ) == .kg
        )
    }
}

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

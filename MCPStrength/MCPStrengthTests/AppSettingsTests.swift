//
//  AppSettingsTests.swift
//  MCPStrengthTests
//
//  Two things about `AppSettings` can actually go wrong, and neither is the
//  field list:
//
//    1. **`current(in:)` returning a different row on a second call.** Every
//       reader in the app resolves settings through it, so a non-deterministic
//       answer means the weight unit can differ between two screens.
//    2. **A default that does not match today's hardcoded behaviour.**
//       Introducing this row must change nothing until something reads it —
//       `defaultRestSeconds` in particular is 90 at every creation site.
//
//  What these tests CANNOT check is the thing most likely to break the app:
//  a missing declaration-level default crashing `ModelContainer(for:)` against
//  an older store. In-memory containers are built from the CURRENT schema, so
//  there is never an old store to migrate (docs/04-status.md § Lessons). Only
//  launching over a previous build's store finds that, which is what the UI
//  tests and the canary procedure are for.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct AppSettingsTests {

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

    // MARK: - Resolution

    @Test func currentCreatesARowOnFirstAsk() throws {
        let context = try makeContainer()
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).isEmpty)

        let settings = AppSettings.current(in: context)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<AppSettings>()).count == 1)
        #expect(settings.weightUnit == .lbs)
    }

    // The load-bearing one. Two calls must be the same row, or two screens can
    // disagree about which unit the user reads in.
    @Test func currentReturnsTheSameRowEveryTime() throws {
        let context = try makeContainer()
        let first = AppSettings.current(in: context)
        try context.save()
        let second = AppSettings.current(in: context)

        #expect(first.id == second.id)
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).count == 1)
    }

    // Duplicates are resolved by age, not fetch order, and the loser is left
    // alone rather than deleted — a hard delete is what AGENTS.md rule 1
    // forbids, and once this syncs a duplicate arriving from another device
    // must not destroy anything.
    @Test func currentPrefersTheOldestRowAndDeletesNothing() throws {
        let context = try makeContainer()
        let older = AppSettings(createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = AppSettings(createdAt: Date(timeIntervalSince1970: 2_000))
        context.insert(newer)
        context.insert(older)
        try context.save()

        #expect(AppSettings.current(in: context).id == older.id)
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).count == 2)
    }

    // A tombstoned row is not the answer, even if it is the oldest.
    @Test func currentIgnoresTombstonedRows() throws {
        let context = try makeContainer()
        let old = AppSettings(createdAt: Date(timeIntervalSince1970: 1_000))
        old.deletedAt = Date(timeIntervalSince1970: 1_500)
        context.insert(old)
        try context.save()

        let resolved = AppSettings.current(in: context)
        #expect(resolved.id != old.id)
        #expect(resolved.deletedAt == nil)
    }

    // MARK: - Defaults

    // Introducing this row must change no behaviour. Every default has to match
    // what the app already does with the value hardcoded, or the first reader
    // silently changes the app.
    @Test func defaultsMatchTheBehaviourAlreadyHardcoded() {
        let settings = AppSettings()

        // 90 is the value at every creation site in Workout.swift and
        // Template.swift. If those change, this test is the reminder.
        #expect(settings.defaultRestSeconds == 90)
        #expect(WorkoutSet(order: 0).restSeconds == settings.defaultRestSeconds)

        // The app is lbs-first and inches-first today.
        #expect(settings.weightUnit == .lbs)
        #expect(settings.measurementWeightUnit == .lbs)
        #expect(settings.distanceUnit == .miles)
        #expect(settings.sizeUnit == .inches)

        // Calendar's numbering, where Sunday is 1.
        #expect(settings.weekStartDay == 1)
    }

    // The three undecided fields start nil, which is what lets their shape
    // change for free. A non-nil default would be a written value, and a
    // written value is the thing that makes an enum migration necessary later.
    @Test func undecidedFieldsStartEmptySoTheirShapeIsStillFree() {
        let settings = AppSettings()
        #expect(settings.theme == nil)
        #expect(settings.language == nil)
        #expect(settings.previousSetBehavior == nil)
    }

    // Sync columns are present but unwired, and `needsSync` defaults true for
    // the reason in Sync/Syncable.swift: the safe failure is pushing twice, not
    // never pushing.
    @Test func syncColumnsArePresentAndDefaultToUnsynced() {
        let settings = AppSettings()
        #expect(settings.needsSync)
        #expect(settings.updatedAt == .distantPast)
        #expect(settings.deletedAt == nil)
    }
}

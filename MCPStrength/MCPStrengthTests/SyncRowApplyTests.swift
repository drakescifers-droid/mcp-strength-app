//
//  SyncRowApplyTests.swift
//  MCPStrengthTests
//
//  Covers writing a pulled row onto a local model — the inverse of
//  SyncRowMapper.
//
//  The strongest test is a round trip: build a model with a distinctive
//  non-default value in every synced field, map it, apply that row onto a
//  SECOND freshly constructed model, and assert field by field. A field
//  that was silently never copied is the bug this file exists to catch,
//  and a default-vs-default comparison cannot see it.
//
//  Numbers are distinct on purpose (not 0, not 1, never the same twice)
//  so a transposition of `order`/`cursor` or `duration`/`restSeconds`
//  cannot pass. Dest starts dirty with placeholder values so a no-op
//  apply fails every assertion, not just the interesting ones.
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct SyncRowApplyTests {

    private let user = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let updated = Date(timeIntervalSince1970: 1_710_000_111)
    private let deleted = Date(timeIntervalSince1970: 1_710_000_222)
    private let lastPerformed = Date(timeIntervalSince1970: 1_710_000_333)
    private let started = Date(timeIntervalSince1970: 1_710_000_444)
    private let completed = Date(timeIntervalSince1970: 1_710_000_555)
    private let recorded = Date(timeIntervalSince1970: 1_710_000_666)

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, ExercisePreference.self, TemplateFolder.self, Template.self,
            TemplateExercise.self, TemplateSet.self, ProgramDay.self,
            Workout.self, WorkoutExercise.self, WorkoutSet.self,
            MeasurementType.self, MeasurementEntry.self,
            AppSettings.self,
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    // MARK: - Exercises

    @Test func exerciseRoundTripsEverySyncedField() {
        let source = Exercise(
            name: "Pendlay Row",
            aliases: ["Barbell Row", "Yates"],
            bodyPart: .back,
            category: .barbell,
            isCustom: true
        )
        source.updatedAt = updated
        source.deletedAt = deleted

        let dest = Exercise(
            name: "PLACEHOLDER",
            aliases: ["wrong"],
            bodyPart: .other,
            category: .cardio,
            isCustom: false
        )
        let destID = dest.id
        #expect(dest.needsSync == true)

        let row: SyncExerciseRow = SyncRowMapper.row(for: source, userID: user)
        SyncRowApply.apply(row, to: dest)

        #expect(dest.name == source.name)
        #expect(dest.aliases == source.aliases)
        #expect(dest.bodyPart == source.bodyPart)
        #expect(dest.category == source.category)
        #expect(dest.isCustom == source.isCustom)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id == destID, "apply must not steal the source id")

        // Per-user fields live on `ExercisePreference`, a different row.
        // Applying an exercise cannot touch them, by construction.
        #expect(dest.preference == nil)
    }

    // MARK: - Templates

    @Test func folderRoundTripsEverySyncedField() {
        // 3 / 7 / 12 are the three ints that a crossed-wire mapper would
        // swap between order, cursor, and totalCycles.
        let source = TemplateFolder(
            name: "Hypertrophy Block",
            order: 3,
            isCollapsed: true,
            kind: .program,
            cursor: 7,
            totalCycles: 12
        )
        source.updatedAt = updated
        source.deletedAt = deleted

        let dest = TemplateFolder(
            name: "PLACEHOLDER",
            order: 99,
            isCollapsed: false,
            kind: .folder,
            cursor: 88,
            totalCycles: 77
        )
        #expect(dest.needsSync == true)

        let row: SyncTemplateFolderRow = SyncRowMapper.row(for: source, userID: user)
        SyncRowApply.apply(row, to: dest)

        #expect(dest.name == source.name)
        #expect(dest.order == 3, "sortOrder must land on order, not cursor")
        #expect(dest.isCollapsed == true)
        #expect(dest.kind == .program)
        #expect(dest.cursor == 7, "programCursor must land on cursor, not order")
        #expect(dest.totalCycles == 12)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    @Test func templateRoundTripsEverySyncedField() throws {
        let context = try makeContext()
        let folder = TemplateFolder(name: "Push Pull", order: 4)
        let source = Template(
            name: "Push A",
            note: "double progression",
            order: 5,
            lastPerformedAt: lastPerformed,
            folder: folder
        )
        source.updatedAt = updated
        source.deletedAt = deleted
        context.insert(folder)
        context.insert(source)

        let dest = Template(
            name: "PLACEHOLDER",
            note: "wrong",
            order: 99,
            lastPerformedAt: started,
            folder: nil
        )
        #expect(dest.needsSync == true)

        let row: SyncTemplateRow = SyncRowMapper.row(for: source, userID: user)
        SyncRowApply.apply(row, to: dest, folder: folder)

        #expect(dest.name == source.name)
        #expect(dest.note == source.note)
        #expect(dest.order == 5)
        #expect(dest.lastPerformedAt == source.lastPerformedAt)
        #expect(dest.folder === folder)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    @Test func templateExerciseRoundTripsEverySyncedField() throws {
        let context = try makeContext()
        let library = Exercise(
            name: "Bench Press", bodyPart: .chest, category: .barbell,
            isCustom: true
        )
        let template = Template(name: "Push A", order: 5)
        let source = TemplateExercise(
            order: 2,
            supersetGroupID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            note: "pause at the bottom",
            stickyNote: "elbows in",
            defaultRestSeconds: 150,
            template: template,
            exercise: library
        )
        source.updatedAt = updated
        source.deletedAt = deleted
        for object in [library, template, source] as [any PersistentModel] {
            context.insert(object)
        }

        let dest = TemplateExercise(
            order: 99,
            supersetGroupID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            note: "wrong",
            stickyNote: "wrong",
            defaultRestSeconds: 30,
            template: nil,
            exercise: nil
        )
        #expect(dest.needsSync == true)

        let row: SyncTemplateExerciseRow = try #require(SyncRowMapper.row(for: source, userID: user))
        SyncRowApply.apply(row, to: dest, template: template, exercise: library)

        #expect(dest.order == 2)
        #expect(dest.supersetGroupID == source.supersetGroupID)
        #expect(dest.note == source.note)
        #expect(dest.stickyNote == source.stickyNote)
        #expect(dest.defaultRestSeconds == 150)
        #expect(dest.template === template)
        #expect(dest.exercise === library)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    @Test func templateSetRoundTripsEverySyncedField() throws {
        let context = try makeContext()
        let parent = TemplateExercise(order: 2)
        // duration 45 and restSeconds 75 are adjacent Ints — the pair a
        // careless apply transposes. sortOrder 2 is a third distinct int.
        let source = TemplateSet(
            order: 2,
            setType: .dropSet,
            weight: 135.5,
            reps: 8,
            repRangeStart: 6,
            repRangeEnd: 10,
            rpe: 8.5,
            distance: 400.25,
            duration: 45,
            restSeconds: 75,
            templateExercise: parent
        )
        source.updatedAt = updated
        source.deletedAt = deleted
        context.insert(parent)
        context.insert(source)

        let dest = TemplateSet(
            order: 99,
            setType: .warmup,
            weight: 9.9,
            reps: 3,
            repRangeStart: 3,
            repRangeEnd: 4,
            rpe: 2.5,
            distance: 11.0,
            duration: 13,
            restSeconds: 14,
            templateExercise: nil
        )
        #expect(dest.needsSync == true)

        let row: SyncTemplateSetRow = try #require(SyncRowMapper.row(for: source, userID: user))
        SyncRowApply.apply(row, to: dest, templateExercise: parent)

        #expect(dest.order == 2)
        #expect(dest.setType == .dropSet)
        #expect(dest.weight == 135.5)
        #expect(dest.reps == 8)
        #expect(dest.repRangeStart == 6)
        #expect(dest.repRangeEnd == 10)
        #expect(dest.rpe == 8.5)
        #expect(dest.distance == 400.25)
        #expect(dest.duration == 45, "durationSeconds must land on duration, not restSeconds")
        #expect(dest.restSeconds == 75)
        #expect(dest.templateExercise === parent)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    // MARK: - Programs

    @Test func programDayRoundTripsEverySyncedField() throws {
        let context = try makeContext()
        let folder = TemplateFolder(name: "Upper / Lower", order: 4, kind: .program)
        let template = Template(name: "Lower A", order: 5)
        let source = ProgramDay(
            order: 6,
            label: "Lower A",
            folder: folder,
            template: template
        )
        source.updatedAt = updated
        source.deletedAt = deleted
        for object in [folder, template, source] as [any PersistentModel] {
            context.insert(object)
        }

        let dest = ProgramDay(order: 99, label: "wrong", folder: nil, template: nil)
        #expect(dest.needsSync == true)

        let row: SyncProgramDayRow = try #require(SyncRowMapper.row(for: source, userID: user))
        SyncRowApply.apply(row, to: dest, folder: folder, template: template)

        #expect(dest.order == 6)
        #expect(dest.label == "Lower A")
        #expect(dest.folder === folder)
        #expect(dest.template === template)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    // MARK: - Workouts

    @Test func workoutRoundTripsEverySyncedField() throws {
        let context = try makeContext()
        let template = Template(name: "Push A", order: 5)
        // durationSeconds 3720 is the Workout field that keeps its row name —
        // not the TemplateSet/WorkoutSet remap. prCount 4 is not 0/1.
        let source = Workout(
            name: "Evening Session",
            startedAt: started,
            completedAt: completed,
            durationSeconds: 3720,
            note: "felt strong",
            totalVolume: 18432.75,
            prCount: 4,
            template: template
        )
        source.updatedAt = updated
        source.deletedAt = deleted
        context.insert(template)
        context.insert(source)

        let dest = Workout(
            name: "PLACEHOLDER",
            startedAt: recorded,
            completedAt: lastPerformed,
            durationSeconds: 99,
            note: "wrong",
            totalVolume: 11.0,
            prCount: 8,
            template: nil
        )
        #expect(dest.needsSync == true)

        let row: SyncWorkoutRow = SyncRowMapper.row(for: source, userID: user)
        SyncRowApply.apply(row, to: dest, template: template)

        #expect(dest.name == source.name)
        #expect(dest.startedAt == source.startedAt)
        #expect(dest.completedAt == source.completedAt)
        #expect(dest.durationSeconds == 3720)
        #expect(dest.note == source.note)
        #expect(dest.totalVolume == 18432.75)
        #expect(dest.prCount == 4)
        #expect(dest.template === template)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    @Test func workoutExerciseRoundTripsEverySyncedField() throws {
        let context = try makeContext()
        let library = Exercise(
            name: "Squat", bodyPart: .legs, category: .barbell,
            isCustom: true
        )
        let workout = Workout(name: "Evening Session", startedAt: started)
        let source = WorkoutExercise(
            order: 4,
            supersetGroupID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            note: "belt on the last set",
            workout: workout,
            exercise: library
        )
        source.updatedAt = updated
        source.deletedAt = deleted
        for object in [library, workout, source] as [any PersistentModel] {
            context.insert(object)
        }

        let dest = WorkoutExercise(
            order: 99,
            supersetGroupID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            note: "wrong",
            workout: nil,
            exercise: nil
        )
        #expect(dest.needsSync == true)

        let row: SyncWorkoutExerciseRow = try #require(SyncRowMapper.row(for: source, userID: user))
        SyncRowApply.apply(row, to: dest, workout: workout, exercise: library)

        #expect(dest.order == 4)
        #expect(dest.supersetGroupID == source.supersetGroupID)
        #expect(dest.note == source.note)
        #expect(dest.workout === workout)
        #expect(dest.exercise === library)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    @Test func workoutSetRoundTripsEverySyncedField() throws {
        let context = try makeContext()
        let parent = WorkoutExercise(order: 4)
        let source = WorkoutSet(
            order: 3,
            setType: .failure,
            weight: 225.25,
            reps: 5,
            rpe: 9.5,
            distance: 1600.5,
            duration: 48,
            restSeconds: 180,
            isCompleted: true,
            completedAt: completed,
            workoutExercise: parent
        )
        source.updatedAt = updated
        source.deletedAt = deleted
        context.insert(parent)
        context.insert(source)

        let dest = WorkoutSet(
            order: 99,
            setType: .normal,
            weight: 9.9,
            reps: 3,
            rpe: 2.5,
            distance: 11.0,
            duration: 13,
            restSeconds: 14,
            isCompleted: false,
            completedAt: nil,
            workoutExercise: nil
        )
        #expect(dest.needsSync == true)

        let row: SyncWorkoutSetRow = try #require(SyncRowMapper.row(for: source, userID: user))
        SyncRowApply.apply(row, to: dest, workoutExercise: parent)

        #expect(dest.order == 3)
        #expect(dest.setType == .failure)
        #expect(dest.weight == 225.25)
        #expect(dest.reps == 5)
        #expect(dest.rpe == 9.5)
        #expect(dest.distance == 1600.5)
        #expect(dest.duration == 48, "durationSeconds must land on duration, not restSeconds")
        #expect(dest.restSeconds == 180)
        #expect(dest.isCompleted == true)
        #expect(dest.completedAt == source.completedAt)
        #expect(dest.workoutExercise === parent)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    // MARK: - Measurements

    @Test func measurementTypeRoundTripsEverySyncedField() {
        let source = MeasurementType(name: "Left Bicep", group: .bodyPart, sortOrder: 9)
        source.updatedAt = updated
        source.deletedAt = deleted

        let dest = MeasurementType(name: "PLACEHOLDER", group: .core, sortOrder: 99)
        #expect(dest.needsSync == true)

        let row: SyncMeasurementTypeRow = SyncRowMapper.row(for: source, userID: user)
        SyncRowApply.apply(row, to: dest)

        #expect(dest.name == source.name)
        #expect(dest.group == .bodyPart, "groupKind must land on group")
        #expect(dest.sortOrder == 9)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    @Test func measurementEntryRoundTripsEverySyncedField() throws {
        let context = try makeContext()
        let type = MeasurementType(name: "Bodyweight", group: .core, sortOrder: 9)
        let source = MeasurementEntry(
            value: 183.2,
            unit: "lb",
            recordedAt: recorded,
            source: .healthKit,
            type: type
        )
        source.updatedAt = updated
        source.deletedAt = deleted
        context.insert(type)
        context.insert(source)

        let dest = MeasurementEntry(
            value: 11.0,
            unit: "kg",
            recordedAt: started,
            source: .manual,
            type: nil
        )
        #expect(dest.needsSync == true)

        let row: SyncMeasurementEntryRow = SyncRowMapper.row(for: source, userID: user)
        SyncRowApply.apply(row, to: dest, type: type)

        #expect(dest.value == 183.2)
        #expect(dest.unit == "lb")
        #expect(dest.recordedAt == source.recordedAt)
        #expect(dest.source == .healthKit)
        #expect(dest.type === type)
        #expect(dest.updatedAt == source.updatedAt)
        #expect(dest.deletedAt == source.deletedAt)
        #expect(dest.needsSync == false)
        #expect(dest.isTombstoned)
        #expect(dest.id != source.id)
    }

    // MARK: - Echo trap and tombstones, asserted directly

    @Test func applyingAPulledRowLeavesTheModelClean() {
        // A dest that starts dirty (the declaration default) must come out
        // clean. If apply dirtied the row, or forgot to clear the flag,
        // the next push would echo the row back to the server forever.
        let source = Workout(name: "Evening Session", startedAt: started)
        source.updatedAt = updated
        let dest = Workout(name: "PLACEHOLDER")
        #expect(dest.needsSync == true)

        let row: SyncWorkoutRow = SyncRowMapper.row(for: source, userID: user)
        SyncRowApply.apply(row, to: dest, template: nil)

        #expect(dest.needsSync == false)
        #expect(dest.updatedAt == updated)
        #expect(dest.deletedAt == nil)
        #expect(dest.isTombstoned == false)
    }

    @Test func aPulledTombstoneStaysATombstone() {
        // A pulled tombstone whose deletedAt is dropped arrives as an
        // ordinary live row and un-deletes itself on this device.
        let source = Workout(name: "Evening Session", startedAt: started)
        source.updatedAt = updated
        source.deletedAt = deleted
        let dest = Workout(name: "PLACEHOLDER")

        let row: SyncWorkoutRow = SyncRowMapper.row(for: source, userID: user)
        SyncRowApply.apply(row, to: dest, template: nil)

        #expect(dest.deletedAt == deleted)
        #expect(dest.updatedAt == updated)
        #expect(dest.isTombstoned)
        #expect(dest.needsSync == false)
    }
}

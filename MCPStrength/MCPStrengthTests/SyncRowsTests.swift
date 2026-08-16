//
//  SyncRowsTests.swift
//  MCPStrengthTests
//
//  Covers turning a SwiftData model into the thing that goes on the wire.
//
//  `supabase/scripts/check_row_mapping.py` already proves the KEYS match the
//  schema. It cannot prove the VALUES are put in the right ones — a mapper that
//  writes `order` into `program_cursor` satisfies every name check ever
//  written. That is what these are for.
//
//  Two areas get the attention, because both fail silently:
//
//    * THE FOUR RENAMED FIELDS. `order`/`cursor`/`group`/`duration` had to be
//      renamed for Postgres reserved words, so they are the four where a
//      crossed wire looks plausible on both sides.
//    * THE ENCODED ENUM STRINGS. docs/05-database.md deliberately spells the
//      Postgres enums the same as Swift's raw values so no mapping table exists
//      to get wrong. If that ever drifts, the column rejects the value and
//      every sync fails — so the encoded JSON is asserted directly.
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct SyncRowsTests {

    private let user = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let when = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, TemplateFolder.self, Template.self,
            TemplateExercise.self, TemplateSet.self, ProgramDay.self,
            Workout.self, WorkoutExercise.self, WorkoutSet.self,
            MeasurementType.self, MeasurementEntry.self,
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    // MARK: - The four renamed fields

    @Test func folderOrderAndCursorDoNotGetCrossed() {
        // Distinct values on purpose: equal ones would let a mapper that swaps
        // the two pass unnoticed.
        let folder = TemplateFolder(name: "Q2 2026", order: 3, kind: .program,
                                    cursor: 7, totalCycles: 2)
        let row = SyncRowMapper.row(for: folder, userID: user)

        #expect(row.sortOrder == 3, "order landed somewhere other than sort_order")
        #expect(row.programCursor == 7, "cursor landed somewhere other than program_cursor")
        #expect(row.totalCycles == 2)
    }

    @Test func measurementGroupBecomesGroupKind() {
        let type = MeasurementType(name: "Left Bicep", group: .bodyPart, sortOrder: 5)
        let row = SyncRowMapper.row(for: type, userID: user)
        #expect(row.groupKind == .bodyPart)
        #expect(row.sortOrder == 5)
    }

    @Test func setDurationBecomesDurationSeconds() throws {
        let context = try makeContext()
        let tx = TemplateExercise(order: 0)
        context.insert(tx)
        // duration and restSeconds are both Ints and adjacent in the struct —
        // exactly the pair a careless mapper transposes.
        let set = TemplateSet(order: 1, duration: 45, restSeconds: 90, templateExercise: tx)
        context.insert(set)

        let row = try #require(SyncRowMapper.row(for: set, userID: user))
        #expect(row.durationSeconds == 45)
        #expect(row.restSeconds == 90)
        #expect(row.sortOrder == 1)
    }

    // MARK: - Relationships become ids

    @Test func aChildCarriesItsParentsID() throws {
        let context = try makeContext()
        let template = Template(name: "Push A", order: 0)
        context.insert(template)
        let tx = TemplateExercise(order: 0, template: template)
        context.insert(tx)

        let row = try #require(SyncRowMapper.row(for: tx, userID: user))
        #expect(row.templateID == template.id)
    }

    @Test func anOrphanedChildIsNotEncodedAtAll() throws {
        // A set with no parent is already corrupt locally. Inventing a uuid to
        // satisfy the NOT NULL column would push that corruption to every other
        // device; returning nil leaves it dirty and retried instead.
        let context = try makeContext()
        let orphan = TemplateSet(order: 0)
        context.insert(orphan)

        #expect(SyncRowMapper.row(for: orphan, userID: user) == nil)
    }

    @Test func anOptionalParentIsAllowedToBeMissing() throws {
        // templates.folder_id is nullable — an unfiled template is normal, not
        // corrupt, and must still push.
        let context = try makeContext()
        let template = Template(name: "Unfiled", order: 0)
        context.insert(template)

        let row = SyncRowMapper.row(for: template, userID: user)
        #expect(row.folderID == nil)
        #expect(row.name == "Unfiled")
    }

    // MARK: - Sync metadata survives the trip

    @Test func aTombstoneCarriesItsDeletedAt() {
        // The delete IS the change. A tombstone encoded without deleted_at
        // arrives as a perfectly ordinary live row, and the deletion is undone
        // on every other device.
        let workout = Workout(name: "Afternoon Workout")
        workout.markDeleted(at: when)

        let row = SyncRowMapper.row(for: workout, userID: user)
        #expect(row.deletedAt == when)
        #expect(row.updatedAt == when)
    }

    @Test func theOwnerIsStampedOnEveryRow() {
        // RLS rejects a row whose user_id is not the caller, so a mapper that
        // dropped this would fail every push with a policy violation.
        let workout = Workout(name: "Afternoon Workout")
        #expect(SyncRowMapper.row(for: workout, userID: user).userID == user)
    }

    @Test func serverOwnedFieldsAreNotSent() {
        // The trigger overwrites server_updated_at on every write anyway, so it
        // is nil going out and only ever populated coming back.
        let workout = Workout(name: "Afternoon Workout")
        #expect(SyncRowMapper.row(for: workout, userID: user).serverUpdatedAt == nil)
    }

    // MARK: - The encoded strings Postgres actually receives

    private func encodedJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func enumsEncodeAsTheExactStringsThePostgresEnumsAccept() throws {
        // Verbatim Swift raw values — `fullBody`, not `full_body`. This is the
        // decision docs/05-database.md made so no mapping layer exists between
        // the two spellings. If it drifts, the column rejects the value and
        // every sync fails on a row nobody can explain.
        let exercise = Exercise(
            name: "Burpee", bodyPart: .fullBody, category: .repsOnly,
            isCustom: true, focusMetric: .totalReps
        )
        let json = try encodedJSON(SyncRowMapper.row(for: exercise, userID: user))

        #expect(json.contains("\"fullBody\""), "body_part enum spelling drifted")
        #expect(json.contains("\"repsOnly\""), "category enum spelling drifted")
        #expect(!json.contains("full_body"))
    }

    @Test func setTypeEncodesAsTheCamelCaseRawValue() throws {
        let context = try makeContext()
        let we = WorkoutExercise(order: 0)
        context.insert(we)
        let set = WorkoutSet(order: 0, setType: .dropSet, workoutExercise: we)
        context.insert(set)

        let json = try encodedJSON(try #require(SyncRowMapper.row(for: set, userID: user)))
        #expect(json.contains("\"dropSet\""))
        #expect(!json.contains("drop_set"))
    }

    @Test func measurementSourceEncodesAsHealthKitNotHealth_kit() throws {
        let entry = MeasurementEntry(value: 180, unit: "lb", source: .healthKit)
        let json = try encodedJSON(SyncRowMapper.row(for: entry, userID: user))
        #expect(json.contains("\"healthKit\""))
    }

    @Test func columnNamesAppearInTheEncodedJSON() throws {
        // A last backstop against the CodingKeys silently not applying: the
        // wire form must be snake_case even though every Swift property is not.
        let workout = Workout(name: "Afternoon Workout", startedAt: when)
        let json = try encodedJSON(SyncRowMapper.row(for: workout, userID: user))

        for key in ["user_id", "started_at", "total_volume", "pr_count", "updated_at"] {
            #expect(json.contains("\"\(key)\""), "missing \(key) in the encoded row")
        }
        #expect(!json.contains("\"userID\""), "a camelCase property leaked to the wire")
        #expect(!json.contains("\"totalVolume\""))
    }

    // MARK: - Every model type has a mapper

    @Test func everySyncedModelCanBeEncoded() throws {
        // Eleven models are Syncable; eleven need a mapper. A type added to the
        // Syncable list without one silently never syncs.
        let context = try makeContext()
        let folder = TemplateFolder(name: "F", order: 0)
        let template = Template(name: "T", order: 0, folder: folder)
        let tx = TemplateExercise(order: 0, template: template)
        let ts = TemplateSet(order: 0, templateExercise: tx)
        let day = ProgramDay(order: 0, folder: folder, template: template)
        let workout = Workout(name: "W")
        let we = WorkoutExercise(order: 0, workout: workout)
        let ws = WorkoutSet(order: 0, workoutExercise: we)
        let type = MeasurementType(name: "Weight")
        let entry = MeasurementEntry(value: 1, unit: "lb", type: type)
        let exercise = Exercise(name: "E", bodyPart: .arms, category: .barbell,
                                isCustom: true, focusMetric: .totalVolume)
        for object in [folder, template, tx, ts, day, workout, we, ws, type, entry, exercise] as [any PersistentModel] {
            context.insert(object)
        }

        #expect(SyncRowMapper.row(for: exercise, userID: user).id == exercise.id)
        #expect(SyncRowMapper.row(for: folder, userID: user).id == folder.id)
        #expect(SyncRowMapper.row(for: template, userID: user).id == template.id)
        #expect(SyncRowMapper.row(for: tx, userID: user)?.id == tx.id)
        #expect(SyncRowMapper.row(for: ts, userID: user)?.id == ts.id)
        #expect(SyncRowMapper.row(for: day, userID: user)?.id == day.id)
        #expect(SyncRowMapper.row(for: workout, userID: user).id == workout.id)
        #expect(SyncRowMapper.row(for: we, userID: user)?.id == we.id)
        #expect(SyncRowMapper.row(for: ws, userID: user)?.id == ws.id)
        #expect(SyncRowMapper.row(for: type, userID: user).id == type.id)
        #expect(SyncRowMapper.row(for: entry, userID: user).id == entry.id)
    }
}

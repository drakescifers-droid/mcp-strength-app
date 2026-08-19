//
//  SyncableTests.swift
//  MCPStrengthTests
//
//  Covers the local sync bookkeeping: the defaults, and the two operations
//  allowed to change them.
//
//  ## What these tests CANNOT cover, and it is the risky part
//
//  The reason `updatedAt`/`deletedAt`/`needsSync` carry DECLARATION-level
//  defaults is SwiftData's lightweight migration, and no test here can check
//  that. In-memory containers are built from the CURRENT schema, so there is
//  never an old store to migrate — the failure is invisible by construction
//  until the app launches against a store written by a previous build. That is
//  what the UI tests are for. See docs/04-status.md.
//
//  What IS testable, and matters just as much, is the DIRECTION each default
//  fails in. `needsSync` defaulting to true is the difference between "pushed
//  twice, which is idempotent" and "never pushed, which is loss" — and it is
//  the kind of thing a later cleanup flips to false because false looks tidier.
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct SyncableTests {

    // MARK: - Defaults

    @Test func aNewRowIsDirtyByDefault() {
        // The whole safety argument in one assertion. If this ever reads
        // `false`, newly created workouts are born claiming to be backed up.
        let workout = Workout(name: "Afternoon Workout")
        #expect(workout.needsSync == true)
    }

    @Test func aNewRowIsNotATombstone() {
        let workout = Workout(name: "Afternoon Workout")
        #expect(workout.deletedAt == nil)
        #expect(workout.isTombstoned == false)
    }

    @Test func aNewRowHasNoEditTimestampYet() {
        // distantPast means "never stamped", which is honest. Defaulting to
        // Date() would date every migrated row to whenever the app was
        // upgraded — a fabricated timestamp that then WINS last-write-wins
        // against genuinely newer remote edits.
        let workout = Workout(name: "Afternoon Workout")
        #expect(workout.updatedAt == Date.distantPast)
    }

    @Test func everySyncedTypeStartsDirty() {
        // Spot-checks one of each shape — root, child, leaf, library entry —
        // so a type added to the conformance list without the properties, or
        // with the wrong default, is caught.
        let syncables: [any Syncable] = [
            AppSettings(),
            Exercise(name: "Back Squat", bodyPart: .legs, category: .barbell),
            ExercisePreference(id: UUID()),
            TemplateFolder(name: "Q2 2026", order: 0),
            Template(name: "Push A", order: 0),
            TemplateExercise(order: 0),
            TemplateSet(order: 0),
            ProgramDay(order: 0),
            Workout(name: "Afternoon Workout"),
            WorkoutExercise(order: 0),
            WorkoutSet(order: 0),
            MeasurementType(name: "Weight"),
            MeasurementEntry(value: 180, unit: "lb"),
        ]

        #expect(syncables.count == 13, "a synced type is missing from this list")
        for row in syncables {
            #expect(row.needsSync == true)
            #expect(row.deletedAt == nil)
            #expect(row.updatedAt == Date.distantPast)
        }
    }

    // MARK: - markEdited

    @Test func markEditedStampsAndDirties() {
        let workout = Workout(name: "Afternoon Workout")
        workout.markSynced()
        // Assert it was CLEAN first, or "becomes dirty" passes vacuously —
        // the trap that hid the Add Template bug (docs/04-status.md).
        #expect(workout.needsSync == false)

        let when = Date(timeIntervalSince1970: 1_800_000_000)
        workout.markEdited(at: when)

        #expect(workout.needsSync == true)
        #expect(workout.updatedAt == when)
    }

    @Test func markEditedOnATombstoneKeepsItDeleted() {
        // Editing a tombstoned row should not resurrect it. Nothing in the app
        // should do this, but "should not happen" is not "cannot happen", and
        // a resurrected workout is a deleted workout coming back on another
        // device weeks later.
        let workout = Workout(name: "Afternoon Workout")
        workout.markDeleted()
        #expect(workout.isTombstoned == true)

        workout.markEdited()
        #expect(workout.isTombstoned == true)
    }

    // MARK: - markDeleted

    @Test func markDeletedTombstonesAndDirties() {
        let workout = Workout(name: "Afternoon Workout")
        workout.markSynced()
        #expect(workout.isTombstoned == false)

        let when = Date(timeIntervalSince1970: 1_800_000_000)
        workout.markDeleted(at: when)

        #expect(workout.deletedAt == when)
        #expect(workout.updatedAt == when)
        #expect(workout.needsSync == true)
        #expect(workout.isTombstoned == true)
    }

    @Test func deletingTwiceDoesNotMoveTheTimestamp() {
        // The retention clock starts at deletedAt. A repeated tap that keeps
        // resetting it means a row nobody is coming back for is kept alive
        // indefinitely, and the 90-day sweep never reaches it.
        let workout = Workout(name: "Afternoon Workout")
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        workout.markDeleted(at: first)

        workout.markDeleted(at: first.addingTimeInterval(86_400))

        #expect(workout.deletedAt == first)
    }

    // MARK: - markSynced

    @Test func markSyncedClearsTheFlagAndNothingElse() {
        let workout = Workout(name: "Afternoon Workout")
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        workout.markEdited(at: when)
        #expect(workout.needsSync == true)

        workout.markSynced()

        #expect(workout.needsSync == false)
        // The edit timestamp must survive: it is the last-write-wins key, and
        // clearing it here would make every synced row lose its next conflict.
        #expect(workout.updatedAt == when)
    }

    @Test func markSyncedDoesNotResurrectATombstone() {
        // A confirmed delete is still a delete. Clearing deletedAt on
        // confirmation would make every successful sync undo the deletion it
        // had just successfully synced.
        let workout = Workout(name: "Afternoon Workout")
        workout.markDeleted()
        workout.markSynced()

        #expect(workout.isTombstoned == true)
        #expect(workout.needsSync == false)
    }

    // MARK: - The schema actually loads

    @Test func theFullSchemaOpensWithTheNewColumns() throws {
        // Not a migration test — it cannot be one — but it does catch a
        // property SwiftData refuses outright, which would otherwise surface as
        // a fatalError on launch rather than a test failure.
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

        let workout = Workout(name: "Afternoon Workout")
        context.insert(workout)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.needsSync == true)
    }

    // MARK: - Querying tombstones

    @Test func tombstonesAreFilterableInAPredicate() throws {
        // Every list in the app will need this filter. If `deletedAt == nil`
        // could not be expressed in a #Predicate, the whole soft-delete design
        // would need rethinking — so it is worth proving once, here, before
        // thirty call sites depend on it.
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

        let kept = Workout(name: "Kept")
        let removed = Workout(name: "Removed")
        context.insert(kept)
        context.insert(removed)
        removed.markDeleted()
        try context.save()

        let live = try context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.deletedAt == nil })
        )

        #expect(live.count == 1)
        #expect(live.first?.name == "Kept")
    }
}

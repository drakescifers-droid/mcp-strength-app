//
//  SyncPlanningTests.swift
//  MCPStrengthTests
//
//  Covers the three rules a sync run makes decisions with: order, cursor, and
//  conflicts. These are the parts where getting it wrong loses data quietly
//  rather than loudly — the network call around them either works or throws.
//

import Testing
import Foundation
@testable import MCPStrength

struct SyncPlanningTests {

    // MARK: - Order

    @Test func pushOrderSatisfiesEveryForeignKey() {
        // The real assertion about `SyncEntity.allCases`: it is a valid
        // topological sort of the dependency graph. Without this, the order is
        // a list anyone can reorder and the failure only appears as a
        // foreign-key violation from the server, mid-run, on a device.
        var seen: Set<SyncEntity> = []
        for entity in SyncEntity.allCases {
            for dependency in entity.dependsOn {
                #expect(
                    seen.contains(dependency),
                    "\(entity) is pushed before \(dependency), which it points at"
                )
            }
            seen.insert(entity)
        }
    }

    @Test func nothingDependsOnItself() {
        for entity in SyncEntity.allCases {
            #expect(!entity.dependsOn.contains(entity), "\(entity) depends on itself")
        }
    }

    @Test func everyTableIsAccountedFor() {
        // Twelve tables in the schema (docs/05-database.md). A table missing
        // from this enum is a table that silently never syncs.
        #expect(SyncEntity.allCases.count == 12)
    }

    // MARK: - Cursor

    @Test func theFirstPullAsksForEverything() {
        // A first sync that started from "now" would leave every row already on
        // the account permanently unpulled — the new device would look empty
        // and nothing would ever correct it.
        #expect(SyncCursor.pullSince(nil) == nil)
    }

    @Test func laterPullsReReadTheOverlapWindow() {
        let cursor = Date(timeIntervalSince1970: 1_800_000_000)
        let since = SyncCursor.pullSince(cursor)
        #expect(since == cursor.addingTimeInterval(-SyncCursor.overlap))
        #expect(since! < cursor, "the window must look BACKWARD, or it skips rows")
    }

    @Test func theCursorAdvancesToWhatWasSeenNotToNow() {
        // Server time, never the device's. A cursor advanced by a local clock
        // drifts past rows the device never received.
        let old = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = old.addingTimeInterval(60)
        #expect(SyncCursor.advanced(from: old, seeing: newer) == newer)
    }

    @Test func anEmptyPullLeavesTheCursorAlone() {
        let cursor = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SyncCursor.advanced(from: cursor, seeing: nil) == cursor)
    }

    @Test func theCursorNeverGoesBackwards() {
        // The overlap window means a pull routinely returns rows OLDER than the
        // cursor. Taking the newest seen without comparing would rewind it a
        // little on every run, and it would never catch up.
        let cursor = Date(timeIntervalSince1970: 1_800_000_000)
        let older = cursor.addingTimeInterval(-3)
        #expect(SyncCursor.advanced(from: cursor, seeing: older) == cursor)
    }

    @Test func theFirstPullSetsTheCursorFromWhatItSaw() {
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SyncCursor.advanced(from: nil, seeing: seen) == seen)
    }

    // MARK: - Conflicts

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aCleanLocalRowAlwaysTakesTheRemote() {
        #expect(
            ConflictResolver.resolve(
                localUpdatedAt: base, localIsDirty: false,
                remoteUpdatedAt: base.addingTimeInterval(60)
            ) == .takeRemote
        )
    }

    @Test func aCleanLocalRowTakesTheRemoteEvenWhenTheRemoteIsOlder() {
        // A clean local row is only ever a copy of what the server already had,
        // so there is nothing to protect and no reason to fight about it.
        #expect(
            ConflictResolver.resolve(
                localUpdatedAt: base, localIsDirty: false,
                remoteUpdatedAt: base.addingTimeInterval(-60)
            ) == .takeRemote
        )
    }

    @Test func aNewerLocalEditSurvives() {
        #expect(
            ConflictResolver.resolve(
                localUpdatedAt: base.addingTimeInterval(60), localIsDirty: true,
                remoteUpdatedAt: base
            ) == .keepLocal
        )
    }

    @Test func anOlderLocalEditLosesAndSaysSo() {
        // Not plain `.takeRemote`: this branch DESTROYS a real user edit. The
        // distinct case is what lets the caller log it, so "my template
        // reverted" is answerable rather than spooky.
        #expect(
            ConflictResolver.resolve(
                localUpdatedAt: base, localIsDirty: true,
                remoteUpdatedAt: base.addingTimeInterval(60)
            ) == .takeRemoteDiscardingLocalEdit
        )
    }

    @Test func aTieGoesToTheUnpushedLocalEdit() {
        // The tie-break protects the copy that could still be lost: an unpushed
        // local edit exists nowhere else, while the remote version is already
        // durable. It also terminates — local pushes, the server takes it.
        #expect(
            ConflictResolver.resolve(
                localUpdatedAt: base, localIsDirty: true, remoteUpdatedAt: base
            ) == .keepLocal
        )
    }

    @Test func discardingIsDistinguishableFromOrdinaryOverwriting() {
        // Guards the distinction itself. If these two ever collapse into one
        // case, the discard log goes silent and nothing announces it.
        #expect(ConflictOutcome.takeRemote != ConflictOutcome.takeRemoteDiscardingLocalEdit)
    }

    // MARK: - What gets pushed

    // TemplateFolder, not Workout: these cover the GENERAL rule, and Workout
    // now carries the unfinished-workout special case, which would make them
    // test two things at once and fail for the wrong reason.
    @Test func aDirtyRowIsPushed() {
        #expect(PushFilter.shouldPush(TemplateFolder(name: "Q2 2026", order: 0)))
    }

    @Test func aCleanRowIsNotPushed() {
        let folder = TemplateFolder(name: "Q2 2026", order: 0)
        folder.markSynced()
        #expect(!PushFilter.shouldPush(folder))
    }

    // MARK: - Unfinished workouts never leave the device

    @Test func anUnfinishedWorkoutIsNotPushed() {
        // The guarantee WorkoutFinishing's hard delete depends on. A workout in
        // progress is a draft: sets appear, get retyped, get discarded at
        // Finish. None of that belongs on the server.
        let workout = Workout(name: "Afternoon Workout")
        #expect(workout.completedAt == nil)
        #expect(workout.needsSync, "fixture is clean, so the assertion below would be vacuous")
        #expect(!PushFilter.shouldPush(workout))
    }

    @Test func aFinishedWorkoutIsPushed() {
        let workout = Workout(name: "Afternoon Workout")
        workout.completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PushFilter.shouldPush(workout))
    }

    @Test func childrenOfAnUnfinishedWorkoutAreNotPushedEither() {
        // Excluding only the workout row would still upload its sets, which is
        // the half-session case this rule exists to prevent — and would leave
        // orphans on the server pointing at a workout that never arrived.
        let workout = Workout(name: "Afternoon Workout")
        let exercise = WorkoutExercise(order: 0, workout: workout)
        let set = WorkoutSet(order: 0, weight: 135, reps: 5, workoutExercise: exercise)

        #expect(!PushFilter.shouldPush(exercise))
        #expect(!PushFilter.shouldPush(set))

        workout.completedAt = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(PushFilter.shouldPush(exercise))
        #expect(PushFilter.shouldPush(set))
    }

    @Test func theWorkoutRuleAppliesThroughTheSyncableOverload() {
        // The engine iterates a heterogeneous list; if the rule is not reached
        // through `any Syncable`, it is decorative.
        let workout = Workout(name: "Afternoon Workout")
        let exercise = WorkoutExercise(order: 0, workout: workout)
        let set = WorkoutSet(order: 0, workoutExercise: exercise)
        for row in [workout, exercise, set] as [any Syncable] {
            #expect(!PushFilter.shouldPush(row))
        }
    }

    @Test func anOrphanedWorkoutChildIsNotPushed() {
        // No workout means nothing can prove it is finished. Defaulting to
        // "push it" would upload a set belonging to nothing.
        let orphan = WorkoutSet(order: 0, weight: 135, reps: 5)
        #expect(!PushFilter.shouldPush(orphan))
    }

    @Test func pendingCountIgnoresUnfinishedWorkouts() {
        // Otherwise the UI reports "12 changes waiting" mid-session for a
        // workout that is not going anywhere until you tap Finish.
        let workout = Workout(name: "In progress")
        let done = Workout(name: "Done")
        done.completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PushFilter.pendingCount([workout, done]) == 1)
    }

    @Test func aTombstoneIsStillPushed() {
        // The delete IS the change. A tombstone that never leaves the device is
        // identical, from every other device's point of view, to never having
        // deleted anything.
        let folder = TemplateFolder(name: "Q2 2026", order: 0)
        folder.markSynced()
        folder.markDeleted()
        #expect(PushFilter.shouldPush(folder))
    }

    @Test func aDeletedFinishedWorkoutStillPushesItsTombstone() {
        // The workout rule must not swallow deletes of workouts that DID reach
        // the server, or deleting a session on one device would never reach the
        // others.
        let workout = Workout(name: "Afternoon Workout")
        workout.completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        workout.markSynced()
        workout.markDeleted()
        #expect(PushFilter.shouldPush(workout))
    }

    @Test func aSeededExerciseIsNeverPushed() {
        // It already exists on the server once, globally, with this exact uuid.
        // Pushing it as owned data violates exercises_custom_iff_owned and
        // fails the whole run on a row the user has never heard of.
        let seeded = Exercise(
            name: "Bench Press (Barbell)", bodyPart: .chest,
            category: .barbell, isCustom: false
        )
        #expect(seeded.needsSync, "the fixture is clean, so this would pass vacuously")
        #expect(!PushFilter.shouldPush(seeded))
    }

    @Test func aCustomExerciseIsPushed() {
        let custom = Exercise(
            name: "Reverse Nordic", bodyPart: .legs,
            category: .repsOnly, isCustom: true
        )
        #expect(PushFilter.shouldPush(custom))
    }

    @Test func theSeededFilterAppliesThroughTheSyncableOverload() {
        // The `any Syncable` overload is what the engine actually calls over a
        // heterogeneous list. If the Exercise special case is not reached
        // through it, the filter is decorative.
        let seeded: any Syncable = Exercise(
            name: "Squat (Barbell)", bodyPart: .legs,
            category: .barbell, isCustom: false
        )
        #expect(!PushFilter.shouldPush(seeded))
    }

    @Test func pendingCountIgnoresSeededExercises() {
        // Otherwise a fresh install reports "25 changes waiting" for a library
        // it ships with and will never send.
        let rows: [any Syncable] = [
            Exercise(name: "Bench Press (Barbell)", bodyPart: .chest,
                     category: .barbell, isCustom: false),
            Exercise(name: "Reverse Nordic", bodyPart: .legs,
                     category: .repsOnly, isCustom: true),
            TemplateFolder(name: "Q2 2026", order: 0),
        ]
        #expect(PushFilter.pendingCount(rows) == 2)
    }

    // MARK: - Seeded measurement types

    // THE FIRST FAILURE A REAL ROUND TRIP PRODUCED, and one the fake transport
    // had accepted for the whole life of the suite. Seeded measurement types
    // exist twice — local rows, and global Postgres rows owned by nobody,
    // sharing baked UUIDs. `needsSync` defaults to true, so unfiltered all 18
    // get pushed as user data; the RLS update policy refuses them with 42501
    // and the WHOLE RUN aborts, so the pull never happens either and every
    // later sync fails the same way.

    @Test func aSeededMeasurementTypeIsNeverPushed() {
        let id = UUID()
        let type = MeasurementType(id: id, name: "Weight", group: .core, sortOrder: 0)
        #expect(type.needsSync, "a new model starts dirty; the filter is the only thing stopping it")
        #expect(!PushFilter.shouldPush(type, seededIDs: [id]))
    }

    @Test func aUserCreatedMeasurementTypeIsPushed() {
        // Not in the seed file, so it is the user's and must travel.
        let type = MeasurementType(id: UUID(), name: "Forearm", group: .bodyPart, sortOrder: 9)
        #expect(PushFilter.shouldPush(type, seededIDs: [UUID()]))
    }

    @Test func aCleanUserCreatedMeasurementTypeIsNotPushed() {
        let type = MeasurementType(id: UUID(), name: "Forearm", group: .bodyPart, sortOrder: 9)
        type.markSynced()
        #expect(!PushFilter.shouldPush(type, seededIDs: []))
    }

    @Test func theGenericFilterAlsoExcludesSeededMeasurementTypes() {
        // pushModels dispatches through `shouldPush(_ row: any Syncable)`, so a
        // rule that only exists on the concrete overload would never run.
        let seeded = MeasurementSeedImporter.seededIDs
        #expect(!seeded.isEmpty, "the bundled seed should be readable from the test host")
        guard let seededID = seeded.first else { return }
        let type = MeasurementType(id: seededID, name: "Weight", group: .core, sortOrder: 0)
        #expect(!PushFilter.shouldPush(type as any Syncable))
        #expect(PushFilter.pendingCount([type]) == 0,
                "a seeded type must not be counted as a change waiting, or the UI reports work that can never clear")
    }

    @Test func theRealSeedIsNotEmpty() {
        // If the bundle read fails, seededIDs is empty and EVERY seeded type
        // becomes pushable again — the exact 42501 that broke the first sync.
        #expect(MeasurementSeedImporter.seededIDs.count >= 18)
    }
}

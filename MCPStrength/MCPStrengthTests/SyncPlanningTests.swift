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

    @Test func aDirtyRowIsPushed() {
        let workout = Workout(name: "Afternoon Workout")
        #expect(PushFilter.shouldPush(workout))
    }

    @Test func aCleanRowIsNotPushed() {
        let workout = Workout(name: "Afternoon Workout")
        workout.markSynced()
        #expect(!PushFilter.shouldPush(workout))
    }

    @Test func aTombstoneIsStillPushed() {
        // The delete IS the change. A tombstone that never leaves the device is
        // identical, from every other device's point of view, to never having
        // deleted anything.
        let workout = Workout(name: "Afternoon Workout")
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
            category: .barbell, isCustom: false, focusMetric: .totalVolume
        )
        #expect(seeded.needsSync, "the fixture is clean, so this would pass vacuously")
        #expect(!PushFilter.shouldPush(seeded))
    }

    @Test func aCustomExerciseIsPushed() {
        let custom = Exercise(
            name: "Reverse Nordic", bodyPart: .legs,
            category: .repsOnly, isCustom: true, focusMetric: .totalReps
        )
        #expect(PushFilter.shouldPush(custom))
    }

    @Test func theSeededFilterAppliesThroughTheSyncableOverload() {
        // The `any Syncable` overload is what the engine actually calls over a
        // heterogeneous list. If the Exercise special case is not reached
        // through it, the filter is decorative.
        let seeded: any Syncable = Exercise(
            name: "Squat (Barbell)", bodyPart: .legs,
            category: .barbell, isCustom: false, focusMetric: .totalVolume
        )
        #expect(!PushFilter.shouldPush(seeded))
    }

    @Test func pendingCountIgnoresSeededExercises() {
        // Otherwise a fresh install reports "25 changes waiting" for a library
        // it ships with and will never send.
        let rows: [any Syncable] = [
            Exercise(name: "Bench Press (Barbell)", bodyPart: .chest,
                     category: .barbell, isCustom: false, focusMetric: .totalVolume),
            Exercise(name: "Reverse Nordic", bodyPart: .legs,
                     category: .repsOnly, isCustom: true, focusMetric: .totalReps),
            Workout(name: "Afternoon Workout"),
        ]
        #expect(PushFilter.pendingCount(rows) == 2)
    }
}

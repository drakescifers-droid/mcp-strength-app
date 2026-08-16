//
//  SyncPlanning.swift
//  MCPStrength
//
//  The decisions a sync run makes, as pure functions — what order to send
//  things in, where to resume from, and who wins a conflict.
//
//  Separated from the transport on purpose, and it is the same split as
//  RepRangeParser and ListOrdering: the network call is boilerplate, while
//  these three rules are where data is silently lost. They are testable here
//  with no server, no session and no clock of their own.
//

import Foundation

// MARK: - Order

/// The synced tables, in the order a run must touch them.
///
/// **Parents before children, and the order is load-bearing in both
/// directions.** Pushing a `template_set` before its `template_exercise`
/// exists is a foreign-key violation, and pulling in the wrong order is the
/// same failure with the rows arriving from the other side.
///
/// Because every operation is an upsert — including deletes, which are updates
/// that set `deleted_at` — there is no reverse pass. Nothing is ever removed by
/// sync, so no child is ever orphaned by it.
enum SyncEntity: String, CaseIterable, Sendable {
    case exercises
    case exercisePreferences
    case templateFolders
    case templates
    case templateExercises
    case templateSets
    case programDays
    case workouts
    case workoutExercises
    case workoutSets
    case measurementTypes
    case measurementEntries

    /// The tables a row of this type points at. Declared separately from the
    /// order above so a test can check the order actually satisfies them —
    /// otherwise `allCases` is just a list somebody can reorder without
    /// noticing that they have.
    var dependsOn: [SyncEntity] {
        switch self {
        case .exercises:            []
        case .exercisePreferences:  [.exercises]
        case .templateFolders:      []
        case .templates:            [.templateFolders]
        case .templateExercises:    [.templates, .exercises]
        case .templateSets:         [.templateExercises]
        case .programDays:          [.templateFolders, .templates]
        case .workouts:             [.templates]
        case .workoutExercises:     [.workouts, .exercises]
        case .workoutSets:          [.workoutExercises]
        case .measurementTypes:     []
        case .measurementEntries:   [.measurementTypes]
        }
    }
}

// MARK: - Cursor

/// Where to resume a pull from.
enum SyncCursor {

    /// How far back to re-read on every pull.
    ///
    /// `now()` in Postgres is TRANSACTION-START time, so two overlapping
    /// transactions can commit out of order: a row whose transaction began
    /// before the cursor can land in the table after it. Re-reading a few
    /// seconds of already-seen rows costs nothing — every apply is an idempotent
    /// upsert — and it is far cheaper than the alternative, which is a row that
    /// silently never arrives and cannot be identified afterwards.
    ///
    /// Five seconds is comfortably longer than any transaction this app runs
    /// and short enough to stay cheap. docs/05-database.md § "Two timestamps".
    static let overlap: TimeInterval = 5

    /// The value to send as `server_updated_at > ?`.
    ///
    /// `nil` means "everything" — the first sync on a device, which must not
    /// silently start from now and leave the account's existing history
    /// unpulled forever.
    static func pullSince(_ cursor: Date?) -> Date? {
        guard let cursor else { return nil }
        return cursor.addingTimeInterval(-overlap)
    }

    /// Advance the cursor after a successful pull.
    ///
    /// Takes the newest `server_updated_at` actually SEEN, never the local
    /// clock: the cursor lives in server time, and mixing in a device's clock
    /// is how it drifts past rows it never received. A pull that returned
    /// nothing leaves the cursor exactly where it was.
    static func advanced(from cursor: Date?, seeing newest: Date?) -> Date? {
        switch (cursor, newest) {
        case (let c, nil):       return c
        case (nil, let n):       return n
        case (let c?, let n?):   return max(c, n)
        }
    }
}

// MARK: - Conflicts

/// What to do with a pulled row that also exists locally.
enum ConflictOutcome: Equatable, Sendable {
    /// Overwrite the local row.
    case takeRemote
    /// Leave the local row alone; it is newer and will be pushed.
    case keepLocal
    /// Overwrite the local row AND record that a local edit was discarded.
    ///
    /// Distinct from `takeRemote` because last-write-wins throws away a real
    /// user edit here, silently and by design. `02-architecture.md` asks for
    /// that to be diagnosable rather than spooky — *"my template reverted"*
    /// should be answerable — so the caller logs both timestamps locally.
    case takeRemoteDiscardingLocalEdit
}

enum ConflictResolver {

    /// Record-level last-write-wins on `updatedAt`.
    ///
    /// TIES GO TO LOCAL when the local row is dirty. An unpushed local edit is
    /// the only copy of that change in existence, while the remote version is
    /// already durable somewhere — so when the two timestamps cannot separate
    /// them, the tie-break protects the copy that could still be lost. It also
    /// terminates: local pushes, the server takes it, and the next pull agrees.
    static func resolve(
        localUpdatedAt: Date,
        localIsDirty: Bool,
        remoteUpdatedAt: Date
    ) -> ConflictOutcome {
        guard localIsDirty else {
            // Nothing local to protect. Take the server's version even when it
            // is older — a clean local row is only ever a copy of something the
            // server already had.
            return .takeRemote
        }
        if localUpdatedAt >= remoteUpdatedAt {
            return .keepLocal
        }
        return .takeRemoteDiscardingLocalEdit
    }
}

// MARK: - What to push

enum PushFilter {

    /// Whether a row should be sent.
    ///
    /// The rule is `needsSync`, with one exception that would otherwise fail
    /// every sync on the account: SEEDED EXERCISES ARE NOT USER DATA. They live
    /// on the server once, globally, with `user_id IS NULL` and the same baked
    /// UUIDs the app ships. Pushing one as owned data violates
    /// `exercises_custom_iff_owned` — the constraint doing exactly its job —
    /// and the run fails on a row the user has never heard of. Filter rather
    /// than discover. docs/05-database.md § Ownership.
    static func shouldPush(_ exercise: Exercise) -> Bool {
        exercise.needsSync && exercise.isCustom
    }

    /// Everything else is simply "has unconfirmed local changes".
    static func shouldPush(_ row: any Syncable) -> Bool {
        if let exercise = row as? Exercise {
            return shouldPush(exercise)
        }
        return row.needsSync
    }

    /// How many local changes are waiting — the number the UI reports.
    static func pendingCount(_ rows: [any Syncable]) -> Int {
        rows.count { shouldPush($0) }
    }
}
